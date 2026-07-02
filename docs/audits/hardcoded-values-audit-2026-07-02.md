# Hardcoded-Values Audit — Portability / Clone-and-Redeploy

**Date:** 2026-07-02
**Author:** platform audit (Claude)
**Question:** What hardcoded values tie this codebase to *this* deployment (accounts, domain, GitHub org, region) and would block a new adopter from cloning the repo, changing a few key variables, and deploying to their own cloud accounts? How hard is each to extract?

**Lens:** Portability. In scope = the identity/tenancy constants an adopter *must* change. A secondary section lists deliberately-pinned values (versions, CIDRs) that are **not** action items. Difficulty is graded by **effort/rewrites/refactoring required**, not wall-clock time.

> **Not an action list yet — a findings report.** No files were changed.

---

## TL;DR

The codebase is in **much better shape than a first grep suggests**. Account IDs, emails, SSO URLs, the state bucket, and the Cloudflare zone already move through the SOPS-encrypted `secrets.enc.yaml`, and the shared modules are mostly variable-driven (cluster names, ARNs, tenant IDs, repo URLs are inputs, not literals). The friction is concentrated in **four identity constants** and a handful of **opinionated defaults + CI/scaffolder literals**.

The four things that actually block a clean fork, worst-first:

| # | Value | Scope | Difficulty | Why |
|---|-------|-------|-----------|-----|
| 1 | `platform.refplat.org` — the **Kubernetes API-group + label-key domain** | ~463 occ. / ~40 files, incl. compiled Go | **HARD** | It's an admission+reconcile *contract*, not a string. Not exposed as any variable. Partial rename silently breaks Kyverno selectors & controller reconcile. Ripples into PromQL/dashboard labels. |
| 2 | `refplat.org` — the **DNS / ingress domain** (`aws.refplat.org`, `preprod.aws.refplat.org`) | ~350 hostname occ. / ~35 units + module defaults | **MEDIUM–HIGH** | Partly variabilized (`base_domain`, `preview_domain`, `grafana_hostname` exist) but no central `base_domain` in the Terragrunt hierarchy; ~32 units + OIDC redirect URIs + scaffolder hardcode the literal. |
| 3 | `asanexample` — the **GitHub org** | 517 occ. | **MEDIUM** | A single `org_name` knob exists in `common.hcl` but isn't threaded. Mechanical-but-wide: Go module path, CODEOWNERS, CI env, bot logins, `trusted-ci` SHA-pinned workflow refs, scaffolder, runbook URLs. |
| 4 | `829808296602` + `us-east-1` — **account ID / region baked into CI & scaffolder** | account 33 occ. outside secrets; region 530 occ. | **LOW–MEDIUM** | Should be repo `vars.*` / config; the correct pattern (`vars.TEST_ROLE_ARN`) already exists in-repo. Scaffolder bakes the ECR account into *every generated app*. |

**Independent counts** (my greps, whole tracked tree): `refplat.org` **814** (of which `platform.refplat.org` **463**); `asanexample` **517**; `us-east-1` **530**; `dkr.ecr.` composite **58**; IAM role-name literals `PlatformDeployer` **239**, `PlatformAdmin` **110**, `TerraformStateAccess` **39**, `OrganizationAccountAccessRole` **80**.

---

## What's ALREADY parameterized (context — do NOT re-flag)

Understanding this is essential to grading difficulty correctly. An adopter *already* changes these without touching code:

- **SOPS `secrets.enc.yaml`** (ADR-066) externalizes: `account_ids`, `admin_email`/`account_emails`, `state_bucket`, `state_role_arn`, `cloudflare_zone_id`, and the ArgoCD/Keycloak SSO SAML URLs + CA. → account IDs, emails, state bucket, SSO are *done*.
- **`org_name = "asanexample"`** exists as a single documented knob in `infra/live/aws/common.hcl:39` ("Change here to rebrand") and is exposed via `_base.hcl` — but only *some* sites consume it (see Finding 3).
- **Shared modules** (`infra/modules/`, non-crossplane) are largely clean: `cluster_name`, cross-account ARNs (via `data.aws_caller_identity` / `var.*_account_id`), tenant IDs (`X-Scope-OrgID` default `"platform"`), and **all ArgoCD repo URLs** are inputs with empty/neutral defaults.
- **Observability Slack/PagerDuty/SNS** wiring is secret-name-driven with empty defaults + External Secrets — hold this up as the *model pattern*.
- **Crossplane runtime** threads `region` / `account_id` / `ecr_registry` / `management_account_id` through the Composition via EnvironmentConfig — the hardcoding there is in defaults/fixtures, not the reconcile path.
- **Dashboards** use templated `${datasource}` UIDs or stable module-internal UIDs — no foreign/hardcoded datasource UIDs or `cluster="…"` filters.

---

## FINDING 1 — `platform.refplat.org` API-group / label-key domain  ·  Difficulty: **HARD**

**The single hardest item. Treat as a coordinated re-domaining project, not a variable extraction.**

`refplat.org` is used two ways that are *not* hostnames:

1. **The Kubernetes API group** of every custom CRD/XRD (`XEnvironment`, `XAgent`, `Team`, `Product`, `Release`, `AccessGrant`, `Person`, `WorkforceRole`) — `group: platform.refplat.org`, `apiVersion: platform.refplat.org/v1beta1`.
2. **The label/annotation key prefix** — `platform.refplat.org/team|product|stage|runtime|otel-export`, finalizer `platform.refplat.org/activation-teardown`, annotation `cost.refplat.org/budget-override`.

These form a **coupling contract**: the Crossplane Composition *writes* these label keys onto namespaces/IAM/quotas; Kyverno policies and RBAC *select on them*. A partial rename silently breaks admission and reconciliation — the worst failure mode (looks fine, quietly wrong).

Where it's embedded (~40 files, ~463 occ.):

- **CRD/XRD `group:`** — `infra/modules/crossplane/charts/{environment-api,agent-api,governance-registry}/templates/*-{xrd,crd}.yaml` (hardcoded literals, **not** Helm-templated). CRD-base **filenames** encode it too: `operators/activation/config/crd/bases/platform.refplat.org_*.yaml`.
- **Composition label-writer** — `crossplane/charts/environment-api/files/composition.yaml` (~32 hits), `agent-api/files/composition.yaml` (8).
- **Kyverno selectors** — `crossplane/charts/environment-policies/templates/*`, `policy/policies-chart/templates/{verify-images,verify-attestations,pod-hardening,namespace-governance,cost-budget-enforce}.yaml`.
- **RBAC apiGroups** — `cluster-rbac/main.tf:87`, `argocd-apps/{delivery,agents,main}.tf`, activation `config/rbac/*_role.yaml`.
- **Compiled Go operator** — `operators/activation/api/v1beta1/groupversion_info.go` (`+groupName=platform.refplat.org`), `internal/controller/activation_controller.go` (finalizer + `+kubebuilder:rbac:groups=` markers), `cmd/main.go:209` `LeaderElectionID: "0a69d8b8.refplat.org"`.
- **Derived Prometheus label** — because the namespace label is `platform.refplat.org/team`, it surfaces in metrics as `label_platform_refplat_org_team`, hardcoded into **PromQL strings and dashboard JSON**: `observability-opencost/dashboards/team-cost.json:42,109`, `observability-opencost/budget-enforcer.tf:19`, `observability-prometheus-agent/main.tf:28,38`.
- **Gate scripts** assert it: `.github/scripts/{roles-gate,people-gate,gitops-gate,teams}/*.sh`.

**Partial mitigation already present but inconsistent:** `policy/policies-chart/values.yaml:37` `environmentNamespaceLabel: platform.refplat.org/team` *is* a value — but only 3 templates reference it; the rest still hardcode `platform.refplat.org/*`. So even the one module that started extracting it isn't self-consistent.

**Proposed:** a single `api_group` / `label_domain` fed through Helm values (charts don't expose it today) **and** a Go build-time `groupName` const. Regenerate CRDs, rebuild the operator.

**Why HARD:** spans ~6 CRDs/XRDs + ~10 Kyverno policies + ~8 RBAC files + the Composition label-writer + CRD-base filenames + compiled Go API types/markers + PromQL/dashboards. Correctness hazard on partial rename. **Realistic recommendation:** decide whether re-domaining is even a goal — an adopter can keep `refplat.org` as an *opaque, arbitrary* group identifier (it never resolves as DNS) and change only the human-facing DNS domain (Finding 2). If so, the action here is **documentation** ("these strings all move together; don't rename piecemeal"), not extraction.

---

## FINDING 2 — `refplat.org` DNS / ingress domain  ·  Difficulty: **MEDIUM–HIGH**

The real hostname domain: apex `refplat.org` → `aws.refplat.org` (platform) / `preprod.aws.refplat.org` (preprod spoke), with service hosts `argocd.`, `keycloak.`/`sso.`, `grafana.`, `backstage.`, `rollouts.`, `*-mimir.`/`*-logs.`/`*-traces.` etc.

**Partly variabilized already** — `base_domain` (crossplane `variables.tf:274`, empty default ✓), `preview_domain` (argocd-apps), `grafana_hostname` (observability). But there is **no central `base_domain` in the Terragrunt hierarchy**, so the literal is hand-written everywhere:

- **~32 live units** hardcode it: `route53/terragrunt.hcl:17` (`aws.refplat.org` zone apex), `gateway`, `external-dns` (`domain_filters`), `keycloak`/`keycloak-config` (incl. OIDC issuer `https://keycloak.aws.refplat.org/realms/platform`), `argocd`, `backstage`, `observability` + spoke push URLs (`preprod-mimir.aws.refplat.org`), `blackbox`, `rollouts-sso`. Both `route53` units + `route53-delegation` carry the literal.
- **Module defaults** encode it: `keycloak/variables.tf:82` `hostname_url` default; `keycloak-config/variables.tf:129–157` the entire `oidc_clients` redirect-URI default block (argocd/backstage/grafana/rollouts URLs); `observability/variables.tf:158` `grafana_hostname` default.
- **Scaffolder** bakes it into generated apps: `scaffolder/.../skeleton/k8s/overlays/prod/progressive.yaml:58,88` → canary analysis reads `https://preprod-mimir.aws.refplat.org/prometheus`. (Good contrast: `skeleton/k8s/base/httproute.yaml` uses a `.invalid` placeholder injected at delivery — the *right* pattern.)
- The apex is split: Cloudflare owns `refplat.org`; Route53 owns the delegated `aws` subdomain (`cloudflare-dns/terragrunt.hcl:60` `subdomain = "aws"`). So it's genuinely **two variables** (`base_domain` + `dns_subdomain`), not one.

**Proposed:** a `base_domain` + `dns_subdomain` pair, cleanest as a new SOPS key (it's environment identity, sits beside `cloudflare_zone_id`), exposed via `_base.hcl` as `include.base.locals.base_domain`, with per-env subdomain (platform→`aws`, preprod→`preprod.aws`). Point module defaults at it or make them empty-required.

**Why MEDIUM–HIGH:** must thread a new accessor through `_base.hcl` and edit ~32 units + the `oidc_clients` default block + scaffolder; also crosses into the gitops registries (Product `domains`, XEnvironment `hostnames`). Coordinated, but no correctness-contract hazard like Finding 1 — a missed spot fails loudly (cert/DNS mismatch).

---

## FINDING 3 — `asanexample` GitHub org  ·  Difficulty: **MEDIUM** (mechanical but wide)

A single `org_name` knob exists (`common.hcl:39`) but 517 occurrences mostly don't consume it. Spread across:

- **Go module path** — `github.com/asanexample/platform/...` in 3 `go.mod` files + ~60 imports + `replace` directives + `telemetry.go` `scopeName`. Mechanical fork-time find-replace; low risk, high count.
- **CODEOWNERS** — `.github/CODEOWNERS` points every path at the personal handle **`@gangster`** (not an org team). An adopter rewrites all entries.
- **CI `env` + bot logins** — `github_org = "asanexample"` in `github-oidc/terragrunt.hcl` (platform + test); `SCAFFOLDER_APP_LOGIN`/`PROMOTE_APP_LOGIN` bot logins in `gitops-gate.yml`; bot identity in `auto-promote/reconcile.sh`; `argocd/terragrunt.hcl` secret `github-asanexample-app-creds`.
- **`trusted-ci` reusable-workflow refs** — scaffolder `skeleton/.github/workflows/{deploy,preview,promote}.yml` call `uses: asanexample/trusted-ci/.github/workflows/*.yml@<sha>`. **This is the trickiest sub-item:** an org rename alone doesn't fix it — the adopter needs their *own* `trusted-ci` repo and must **re-pin the SHAs** to commits in that repo.
- **Scaffolder Backstage templates** — `owner=asanexample&repo=platform` on every `publish:github`/`fetch` action across `scaffolder/templates/*/template.yaml`.
- **Runbook URLs** — `observability/alerts/curated.yaml` has **38** `runbook_url: https://github.com/asanexample/platform/...` (one per alert). Bulk replace, but inside a static YAML consumed as-is (needs `templatefile()` or a documented sed).
- **Product registry** — `gitops/products/**` `repo: asanexample/alpha-*` (example content — adopter replaces).

**Proposed:** repoint the two `github_org` units at the existing `org_name` local; promote CI `env` literals + bot logins to repo `vars.*`; template the runbook base URL; parameterize the scaffolder `owner`. The Go module path and `trusted-ci` refs are inherent fork-time rewrites.

**Why MEDIUM:** no logic changes, but touches Go tooling, CI, gates, and scaffolder; the `trusted-ci` SHA re-pin is a real dependency an adopter must stand up separately.

---

## FINDING 4 — Account ID / region baked into CI & scaffolder  ·  Difficulty: **LOW–MEDIUM**

Real account `829808296602` appears **33× outside** `secrets.enc.yaml`, and `us-east-1` **530×**. Most are already variables/config; the leaks are in CI, scaffolder, and a few defaults.

- **CI workflow `env`** (should be repo `vars.*` — `test-aws.yml:13,46` already proves the pattern with `vars.TEST_ROLE_ARN`):
  - `auto-promote.yml`, `runner-smoke.yml` → `DEPLOYER_ARN: arn:aws:iam::829808296602:role/PlatformDeployer`, `CLUSTER_NAME: platform-use1-eks`, `AWS_REGION: us-east-1`.
  - `gha-runner-image.yml`, `operator-image.yml` → `ECR_REGISTRY: 829808296602.dkr.ecr.us-east-1.amazonaws.com`, ECR push-role ARN.
  - `teams-apply.yml:43` → `BASE: infra/live/aws/platform/us-east-1/platform` (region-in-path couples CI to the directory layout).
- **Scaffolder skeleton** bakes the ECR account into **every generated app**: `k8s/overlays/{dev,test,uat,staging,prod}/kustomization.yaml` + `rollout.yaml:84` all reference `829808296602.dkr.ecr.us-east-1.amazonaws.com`. This is the highest-leverage scaffolder fix — it propagates to every product.
- **`.platctl.yaml`** — correct *location* for adopter config, but heavily this-deployment: `PlatformAdmin`/`PlatformDeployer` role ARNs per account, `state_bucket: tfstate-mgmt-851725353202`, cluster names `platform-use1-eks`/`preprod-use1-eks`, account IDs. (Docs use the template form `tfstate-mgmt-<MGMT_ACCOUNT_ID>` — good.)
- **`root.hcl` state backend** — `root.hcl:18` `region = "us-east-1"` and `root.hcl:20` `dynamodb_table = "terraform-locks"` are hardcoded even though `aws_region` is overridable at line 89. **Chicken-and-egg:** read at init before `_base.hcl` locals resolve, so they must join the raw `_secrets` map like `state_bucket` does. Also `mgmt/global/state-access/terragrunt.hcl:64` hardcodes the table + region in the IAM ARN.
- **Module defaults** encoding this deployment: `backstage/variables.tf:55` default `829808296602.dkr.ecr.us-east-1.amazonaws.com`; `policy/variables.tf:262` `ecr_region` default `us-east-1`; `us-east-1` defaults on `aws_region` across ~6 modules (already vars, just opinionated defaults).

**Note — genuinely region-pinned (leave as-is):** `aws/cost-export/main.tf:127,148` and `observability-opencost` `cur_athena_region` — CUR/billing is a us-east-1-only AWS service.

**Why LOW–MEDIUM:** most are default swaps or `env`→`vars.*` promotions with an established in-repo pattern; the `root.hcl` state-region is the only structurally awkward one (init-time, chicken-and-egg).

---

## FINDING 5 — Smaller extractions  ·  Difficulty: **TRIVIAL–LOW**

Genuine "literal that should be a variable," each self-contained:

- **`pagerduty/main.tf:52`** `time_zone = "America/Los_Angeles"` → `oncall_time_zone` var. Trivial.
- **Tailscale operator tag** — `tailscale/main.tf:16` `defaultTags = ["tag:k8s-operator"]` is a literal while `tailscale-admin/variables.tf:39` has the *same value as a var*. Promote the `tailscale` side to a shared input so the two can't drift. Low.
- **Tailnet name** — `taild3190d.ts.net` hardcoded in 3 units (`tailscale`, `tailscale-admin` × platform + preprod). Adopter-specific → new SOPS key `tailnet`. Low (inside provider-gen heredocs).
- **`github_org` → existing `org_name`** — the 2 `github-oidc` units (Finding 3) can just read `include.base.locals.org_name`. Trivial.
- **Branding tags** — `common.hcl:42–51` (`Project = "Multi-Cloud Platform"`, `CostCenter`, `Owner = "Platform Team"`) + duplicated in every `env.hcl`. Cosmetic; centralize in `common.hcl`. Trivial.
- **`identity-center/terragrunt.hcl:164`** hardcodes anchor username `"josh"` as the mgmt-contact special case. Low.
- **IAM role *names*** — `PlatformDeployer`/`PlatformAdmin`/`TerraformStateAccess`/`activation-operator-identity-center` are cross-module/cross-account *contract names* (ARNs are threaded; the names are the convention). Changing one requires the matching mgmt-IAM change — Medium, but an adopter would most likely keep them. Flag as "convention, keep unless rebranding."
- **Test fixtures / gate tests** carry real account IDs + org + ECR host (`policy/.kyverno-tests/*`, `crossplane/.environment-api-tests/*`, `.github/scripts/gitops-gate/test-*.sh`). Low value; parameterize via env/`--set` if the fixtures are ever made portable.

---

## Likely-INTENTIONAL — not action items (recorded so nothing is silently omitted)

- **CIDR blocks** — per-env VPC/pod CIDRs in `network.hcl` (`10.100.0.0/16` etc.), AZ literals, EKS service CIDR. Deliberate `/16`-per-env design; correctly localized to `network.hcl`/`region.hcl` (the intended override point). *One nit:* Tailscale `advertise_routes`/split-DNS IPs (`10.100.0.2`) are hand-copied from `vpc_cidr` rather than `cidrhost(vpc_cidr, 2)`, so they can drift.
- **Tool / chart version pins** — `_versions.hcl` (cilium 1.19.4, argocd, kyverno 3.8.1, …) + module `versions.tf`. Deliberate single-source pins (ADR-083). An adopter keeps these.
- **Region-in-directory-path** (`infra/live/aws/us-east-1/…`) — structural; a region change is a directory rename + `region_abbv`/cluster-name derivation, not a variable. Only matters for a multi-region or non-us-east-1 adopter.
- **ARN partition `aws`** — hardcoded everywhere (not `aws-us-gov`/`aws-cn`). Only matters for GovCloud/China adopters. Low priority.
- **Bedrock `us.anthropic.*` inference-profile prefix** (`gitops/agents/triage-copilot.yaml`) — the `us.` prefix is region-partition-coupled; a non-US adopter changes it. Sample/registry content.
- **Upstream constants** — Helm repo URLs, AWS-managed policy ARNs, API groups (`aws.upbound.io`, `crossplane.io`, `rbac.authorization.k8s.io`), PagerDuty vendor `"Prometheus"`. Not org-specific.
- **`gitops/**` sample registry** — teams/products/environments/people are example content an adopter replaces wholesale (incl. Slack channel `C0BDL14RN8Z` in `gitops/teams/alpha.yaml`, product `repo:` values). Not "hardcoding" — data.

---

## Recommended sequencing (if/when you act)

The two efforts are independent and can be tackled in either order; within each, do the cheap wins first to build the pattern.

1. **DNS domain (Finding 2)** — introduce `base_domain`/`dns_subdomain` in SOPS + `_base.hcl`, then sweep units + module defaults + scaffolder. Fails loud, so low risk. This alone gets an adopter *most* of the way to "deploy to my domain."
2. **Account/region CI + scaffolder hygiene (Finding 4) + small extractions (Finding 5)** — mechanical, pattern already exists (`vars.TEST_ROLE_ARN`). Biggest bang: the scaffolder ECR-account fix (touches every future app).
3. **GitHub org (Finding 3)** — thread `org_name`; the Go module path + `trusted-ci` SHA re-pin are inherent fork-time steps — **document them** rather than trying to variabilize.
4. **API-group domain (Finding 1)** — **decide first whether this is even a goal.** Recommend: keep `refplat.org` as an opaque group identifier, document "these move together," and *don't* attempt a piecemeal rename. Only invest if white-labeling the API surface is a real product requirement — then it's a dedicated, tested re-domaining project (charts expose `api_group`, Go `groupName` const, regen CRDs, rebuild operator).

**A note on "clone and deploy":** even with all of the above, an adopter still needs to stand up prerequisites that aren't repo variables — their own SOPS/KMS key, a `trusted-ci` repo, a Cloudflare zone, a Tailscale tailnet, Keycloak SAML apps, and the GitHub Apps the scaffolder/gates use. Worth capturing those in an `ADOPTING.md` alongside the variable work; variable extraction is necessary but not sufficient for one-command portability.
