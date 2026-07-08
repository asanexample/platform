# Platform

## Project Overview

Multi-cloud IaC platform using OpenTofu (v1.12.1) + Terragrunt (v1.0.7). Currently targets AWS only (Azure/GCP removed). CLI tool versions (tofu, terragrunt, kubectl, helm, awscli) are pinned canonically in `/.tool-versions` — the single source of truth read by local dev (mise/asdf), CI, and the self-hosted runner image.

- **Shared modules**: `infra/modules/` (`ls` for the current list) — includes the LGTM+P observability stack as `observability` + 19× `observability-*`
- **AWS modules**: `infra/modules/aws/`
- **Live configs**: `infra/live/aws/` -- environment-specific Terragrunt units

## House Skills

Project-level agent skills under `.claude/skills/` hold the deep, verified how-to for common
tasks and load automatically when relevant. Prefer them over re-deriving from this file:

- **terraform-style** — module `.tf` house style (section-header `main.tf`, no provider blocks, `versions.tf`)
- **terragrunt-units** — authoring `infra/live/**/terragrunt.hcl` (includes, `module_source`, `mock_outputs`)
- **authoring-k8s-workloads** — Kyverno-compliant manifests for environment namespaces
- **apply-and-destroy** — the `run --all` apply/destroy commands + deployment ordering
- **platctl** — the DAG-aware bootstrap / teardown / validate / park orchestrator
- **cluster-parking** — parking/unparking environments overnight (`platctl down`/`up`, scale node groups to zero)
- **cluster-access** — kubectl/EKS access on the private clusters (Tailscale; never the public endpoint)
- **environment-onboarding** — provisioning a Product/Environment via the registries + `XEnvironment` claim
- **supply-chain-onboarding** — wiring an app's CI to the shared signing/provenance workflows
- **authoring-adrs** — writing/evolving ADRs in `docs/adrs/`
- **kyverno-policy-authoring** — authoring ClusterPolicies in the `policy` module (producer side; vs `authoring-k8s-workloads` consumer side)
- **crossplane-composition-authoring** — editing the XEnvironment XRD + Composition (provisioner internals; vs `environment-onboarding` claim use)
- **argocd-app-delivery** — ArgoCD ApplicationSets, PR previews, Release-keyed delivery, platform vs tenant roads
- **observability-authoring** — adding dashboards/alerts/SLOs + instrumenting workloads in the LGTM+P stack
- **backstage-portal** — configuring the Backstage portal/plugins/auth/catalog from the infra `backstage` module
- **maintaining-docs** — keeping docs current as code changes (the doc-impact map, grep-first for renames, the drift traps); use when finishing a feature / opening a PR
- **triaging-issues** — keeping the GitHub issue board current (verify status against primary sources not the roadmap/body, the origin/main-vs-worktree trap, close/keep-open/relabel rules); use when triaging issues, closing shipped work, or reconciling the board after merges
- **authoring-platform-agents** — authoring/operating a platform agent (the `XAgent` claim, envelope, kill-switch; ADR-082)
- **skill-self-correction** — durably fixing a house skill (under `.claude/skills/`) when it misleads you

**Vendored (third-party).** `terraform-skill` is a community skill (antonbabenko/terraform-skill,
Apache-2.0) vendored + pinned for diagnostic Terraform/OpenTofu depth — failure-mode routing,
`count`/`for_each` churn, `moved`/`import`/`removed`, `write_only` secrets, state recovery. It is
generic Terraform (not Terragrunt-aware), so the `terraform-style` / `terragrunt-units` house skills
win on conflict (no provider/backend blocks in modules here). Source + audit:
`.claude/skills/terraform-skill/PROVENANCE.md`.

## Terragrunt Config Hierarchy

> Authoring or editing units: the **`terragrunt-units`** skill.

```text
root.hcl              Remote state (S3), providers, terraform_binary
  └─ common.hcl       Cloud-wide defaults, loads secrets (SOPS secrets.enc.yaml), tags
      └─ env.hcl      Account ID (from secrets), env tags
          └─ region.hcl / network.hcl    Region, CIDRs
              └─ workload.hcl            Workload name, compliance tier
                  └─ terragrunt.hcl      Unit-level inputs and dependencies
```

`_base.hcl` loads all layers and exposes them to units via `include.base.locals.*`. Units include it as:

```hcl
include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}
```

### Secrets

Sensitive values (account IDs, emails, SSO URLs) live in `infra/live/aws/secrets.enc.yaml` — **SOPS-encrypted and committed** to git, decrypted at plan/apply via the management `platform-sops` KMS key (ADR-066). `root.hcl`/`common.hcl` set `_secrets = sops_decrypt_file(...secrets.enc.yaml)`; `TG_SOPS_BOOTSTRAP=1` is the greenfield escape that falls back to a local plaintext `infra/live/aws/secrets.hcl` (gitignored) — needed only on a true from-zero bootstrap before the KMS key exists. `_secrets` is then exposed through `_base.hcl`:

```hcl
include.base.locals.account_ids["platform"]   # AWS account ID
include.base.locals.account_id                 # current env's account ID
include.base.locals.admin_email                # contact email
include.base.locals.account_emails["preprod"]  # per-account email
```

## Deployment Ordering & Apply/Destroy (AWS)

> Applying/destroying a unit, bootstrapping/tearing down, or reasoning about what depends on what:
> the **`apply-and-destroy`** and **`platctl`** skills own this — the full DAG, the exact `run --all`
> commands, and the per-unit "why" (Keycloak self-routing, the ESO→argocd chain, Karpenter's
> Cilium-first taint, etc.) live there and in `docs/runbooks/platform-rebuild-from-scratch.md`.

The one fact worth keeping resident: the EKS API is **private-only by design** (ADR-010) — reach it
over **Tailscale**, never the public endpoint, for routine ops. The only exception is a full
from-scratch teardown/rebuild, where `platctl` bootstraps/locks down the public endpoint automatically.

**⚠️ NEVER run `terragrunt apply`/`plan` from a git worktree** — always apply from the main checkout.
Several teardown/drain `null_resource`s (crossplane's orphan-sweeps, plus the namespace-drain/CNPG-cleanup
resources in backstage/keycloak/platform-directory/tailscale/observability) used to bake an absolute
`scripts/*.sh` path into their `triggers`; a worktree's different absolute path made Terraform see a
changed trigger, replace the resource, and fire its `when = destroy` provisioner — force-deleting live
environment IAM roles + ECR repos on what looks like a routine apply. That specific mechanism is fixed
(the script path is now resolved at run time via `git rev-parse --show-toplevel`, never baked into
`triggers`) — but the rule stays until the fix has proven out across real applies from a worktree.

## Key Commands

```bash
# Plan/apply from any live unit directory
terragrunt plan
terragrunt apply

# Bootstrap/teardown (preferred)
platctl bootstrap
platctl bootstrap --dry-run
platctl teardown

# Validate deployed infrastructure
platctl validate
platctl validate --env platform
platctl validate --check tailscale

# Configure kubectl contexts
platctl kubeconfig

# Format checks
tofu fmt -check -recursive infra/modules/
terragrunt hcl fmt --check

# Tests (Terratest, Go)
cd infra/tests/aws/<module> && go test -v -timeout 30m

# Private cluster access (full guidance: the `cluster-access` skill)
./scripts/eks-tunnel.sh <cluster-name> <region> [instance-id]  # instance-id auto-discovered if omitted
```

## Pre-commit Hooks

`.githooks/pre-commit` runs tofu fmt, terragrunt hcl fmt, and tofu validate on staged files. Activate with:

```bash
git config core.hooksPath .githooks
```

## Git Workflow

Branches are kebab-case with a short type or domain prefix, e.g. `docs-`, `feat-`, `fix-`, or a
domain word like `cost-`/`adr-`/`govreg-` (check `gh pr list --state merged --json headRefName`
for precedent if unsure). `EnterWorktree`'s auto-generated `worktree-*` branch name doesn't follow
this — rename it (`git branch -m`) before opening a PR.

## Module Code Style & Testing

Full house style: the **`terraform-style`** skill. In brief — organize `main.tf` with `# ---`
banner section headers grouping related resources (IAM, KMS, …); modules declare **no** provider
blocks (Terragrunt injects them). Tests are **Terratest (Go)** under `infra/tests/aws/<module>/`
(fixtures in `fixtures/`), plan-only for modules that can't be safely apply/destroyed in CI, and
must set `TerraformBinary: "tofu"`.

## AWS Accounts

Real account IDs are in the SOPS-encrypted `infra/live/aws/secrets.enc.yaml` (committed; KMS-decrypted, ADR-066). See `infra/live/aws/secrets.hcl.example` for the structure.

Cross-account access uses purpose-built IAM roles (see IAM Roles below). `OrganizationAccountAccessRole` retained as break-glass only.

The **Test** account (`157263244316`, Terratest sandbox) is a standard `PlatformDeployer`-managed account; an org SCP (`DenyTeamTagTampering`) forbids human SSO admins from tagging IAM, so its IaC runs via `PlatformDeployer` like every other account. Setup, the one-time bootstrap, and the apply procedure: `docs/runbooks/test-sandbox-account.md`.

## IAM Roles

| Role | Account | Purpose |
|------|---------|---------|
| **PlatformAdmin** | Platform, PreProd | kubectl operate/debug + SSM tunnel — least-privilege (read+operate, NOT author; cluster authoring via ArgoCD, AWS via PlatformDeployer, emergencies via break-glass — ADR-040) |
| **PlatformDeployer** | Platform, PreProd | Terragrunt apply, Helm/K8s providers |
| **DeveloperAccess-\<team\>** | PreProd | Per-team, namespace-scoped kubectl (design: one role per team + an EKS access entry → the team's per-Environment `<team>-<product>-<stage>:developers` group bound to the `environment-developer` ClusterRole; group-mapped RBAC — ADR-039). **⚠️ NOT currently provisioned** — the v3 Composition emits only the in-cluster RoleBinding, not the IAM role/access entry (#647 closed as superseded by the cluster-access design in #364 / ADR-068; capability still unbuilt); use `platctl kubeconfig`/PlatformAdmin until built |
| **TerraformStateAccess** | Management | S3 state bucket + DynamoDB lock table |
| **OrganizationAccountAccessRole** | All accounts | Break-glass only |

- Terragrunt providers assume **PlatformDeployer** (via root.hcl)
- Helm/K8s exec auth uses **PlatformDeployer** (via `include.base.locals.deployer_role_arn`)
- kubectl uses **PlatformAdmin** (`aws eks update-kubeconfig --role-arn ...PlatformAdmin`)
- State backend uses **TerraformStateAccess** (via root.hcl remote_state `role_arn`)

## Architecture Decisions

- **Cilium as CNI** (1.19.4) — BYOCNI on EKS, `kubeProxyReplacement = true`. Shared module uses `cloud_provider` variable.
- **East-west zero trust (ADR-057)** — Cilium **WireGuard** transparent pod-to-pod encryption is fleet-default and live on **both clusters** (`encryption_enabled`); Cilium **mutual authentication** with an embedded **SPIRE** (SPIFFE workload identity — `mutual_auth_enabled`) is a **preprod showcase** securing the alpha-shop↔alpha-checkout call (`authentication.mode: required` CNP; `AUTH TYPE=spire`). Enabling either is a rolling Cilium restart; fleet-wide/tier-gated auth enforcement is a follow-up. Cross-namespace calls need **both** egress (caller) + ingress (callee) netpol halves.
- **Cilium Gateway API** — external Envoy uses reserved `ingress` identity (8), not `host`. Environment CiliumNetworkPolicies must allow `fromEntities: ["ingress"]`. TLS secrets copied to `cilium-secrets` namespace.
- **SSM Session Manager** — fallback for private cluster access when Tailscale is unavailable (no VPN needed); Tailscale is the primary path (ADR-010).
- **Hubble TLS** uses `helm` method on AWS to avoid BYOCNI chicken-and-egg with post-install hooks.
- **Node groups separated** from EKS module to enforce Cilium-first ordering.
- **EKS add-ons separated** — coredns can't schedule until CNI + nodes are ready.
- **ArgoCD SSO** — direct Keycloak OIDC (Dex retired, ADR-053/059); ArgoCD brokers OIDC straight to Keycloak, so the unit runs after `keycloak-config` and pulls its client secret via External Secrets.
- **Argo Rollouts (ADR-056)** — progressive delivery (canary/blue-green) for all workloads; the `argo-rollouts` module deploys the controller + dashboard, the latter fronted by `oauth2-proxy` for Keycloak SSO (no native auth). Metric-gated canary + burn-rate SLO analysis.
- **Per-team PagerDuty on-call** — Phase 2 of the identity-directory ADR (ADR-084, "Platform Identity Directory and Owner Resolution"), not a dedicated PagerDuty ADR; the `pagerduty` module provisions per-team on-call schedules/escalation in IaC, and the owner-routing agent resolves the culprit's team via the `platform-directory` identity directory and routes/@mentions accordingly.
- **Transit Gateway** — hub in platform account, shared to spokes via RAM. Dedicated /28 transit subnets per AZ.
- **Cross-VPC DNS** — three modes via `dns_method`: `phz` (custom PHZ, cheap, manual IP updates), `resolver_outbound`, or `resolver_inbound` (Route53 Resolver endpoints, robust, ~$365/mo). EKS-managed PHZs are inaccessible, so we maintain our own.
- **Tailscale Operator** — subnet router advertising VPC CIDR to tailnet. Split DNS managed by `tailscale` K8s unit. OAuth from Secrets Manager.
- **Internal Gateway NLB** — `internal` scheme, services only reachable through Tailscale. TLS via Let's Encrypt DNS-01.
- **Team→Product→Service→Environment model (ADR-067)** — ownership (Team) decoupled from the deployment unit (Environment = a Product at a Stage). ECR: `team-<team>/<product>-<svc>`. Namespace isolation only; vCluster deferred (ADR-033). Environments are provisioned by the Crossplane `Environment` Composition via an `XEnvironment` claim (`gitops/environments/<team>/<product>/<stage>.yaml`) — the sole provisioner; the old v2 `tenant`/`tenant-claims`/`pod-identity`/`s3-shared` units are retired. Registries-as-single-source (ADR-069, refining ADR-061; also ADR-063/067): the git-native `Team` CR (`gitops/teams/`), `Product` registry (`gitops/products/<team>/<product>.yaml` — repo, tenancy, domains), and `XEnvironment` claims (`gitops/environments/`) are the source of truth — `argocd-apps`, `policy`, and `github-oidc` derive (`fileset`+`yamldecode`) per-Product from the registry; the app-delivery `teams.hcl` is retired. Deprovisioning (ADR-062 #283): `spec.lifecycle.phase: decommissioning` is a reversible suspend (the Composition zeroes the ResourceQuota); the hard-delete (claim removal) is gated decommission-first + admin-reviewed by the gitops Gate, and ECR is retained (`deletionPolicy: Orphan`). See `docs/runbooks/environment-deprovisioning.md` and `docs/architecture/crossplane-environment-api.md`.
- **PR preview environments (ADR-032)** — designed but **not implemented on the v3 delivery model** (the v2 mechanism it describes — a per-app PR-generator ApplicationSet, `preview = true` in `teams.hcl` — was removed at the v3 cutover). What exists today is `preview_domain`: the standard per-Product ApplicationSet rewrites each Environment's `HTTPRoute` hostname to `<product>-<team>-<stage>.<preview_domain>` — a per-stage rewrite, not a per-PR ephemeral environment.
- **Kyverno policy engine** (3.8.1 / app v1.18.1, ADR-014) — `policy` module deploys the HA engine + a bundled local `policies-chart` of ClusterPolicies, layered above the PSA `baseline` floor. Per-product image-registry scoping + cross-team IRSA-annotation backstop (environment AWS access is Pod Identity, ADR-041) + RBAC hardening. **Audit-first** (`validation_failure_action`) then flip to Enforce. No team data in the module (per-product maps derived from the `Product` registry at the unit — `verify_subjects_product` embeds `spec.repo`; the v2 `attest_caller_repos` variable is retired). **Supply-chain split (ADR-046)**: per-product `restrict-images`/`restrict-route-hostnames` are owned by the Crossplane Environment Composition; the platform-owned cosign/SLSA `verify-images-product`/`verify-attestations-product` stay here for all products. Phased rollout (Phases 2–5: mutate/generate, cosign verifyImages, CLI shift-left, reporting/cleanup).

## Authoring Policy-Compliant Workloads (Kyverno)

Kyverno is in **Enforce** mode on **preprod and platform** — non-compliant resources in environment
namespaces (those labeled `platform.refplat.org/team`, named `<team>-<product>-<stage>`, e.g. `alpha-demo-dev`)
are **rejected at admission**. Full authoring guidance is the **`authoring-k8s-workloads`** skill (and
**`supply-chain-onboarding`** for image signing); this resident list is the quick reference. Full
per-cluster catalog: `docs/architecture/kyverno-policy-catalog.md`. When writing environment manifests
(app repos' `k8s/`, or anything applied to an environment namespace):

**Auto-injected by `mutate` — do NOT bother setting (Kyverno adds them when absent):**

- Container `securityContext`: `allowPrivilegeEscalation: false`, `capabilities.drop: [ALL]`, `seccompProfile.type: RuntimeDefault`
- Pod `automountServiceAccountToken: false`
- The `team` label (derived from the namespace name)
- **Graceful-drain defaults** (ADR-085): a container `lifecycle.preStop` sleep + pod `terminationGracePeriodSeconds: 30`, and `topologySpreadConstraints` (zone + node, soft, selector derived from your workload) — so deploys/disruptions don't drop traffic

**Auto-generated for you — do NOT author (ADR-085):**

- A **`PodDisruptionBudget`** (`<workload>-pdb`, `maxUnavailable: 1`, selector derived from your workload) per environment Deployment/StatefulSet — created, kept in sync, GC'd with the workload. Drain-safe; only meaningful at **≥ 2 replicas**.

**Required — omitting these gets the resource REJECTED:**

- **Image** from the platform ECR **scoped to the team/product**: `<platform-acct>.dkr.ecr.us-east-1.amazonaws.com/team-<team>/<product>-<svc>:<tag>` (cross-team images are denied)
- An **explicit, immutable image tag** — never `:latest`, never untagged
- **Resource requests AND limits** (cpu + memory) on every container
- **`livenessProbe` and `readinessProbe`** on every container
- Services must be **`ClusterIP`** — `LoadBalancer`/`NodePort` are denied (ingress is via the shared Gateway / `HTTPRoute`)
- **HTTPRoute/GRPCRoute/TLSRoute hostnames** must be in the team's allow-list (the `Environment` claim's `hostnames`) — claiming another team's or a platform hostname (or omitting hostnames) is denied (ADR-029)
- Workloads only in environment namespaces (`<team>-<name>-<env>`, e.g. `alpha-demo-dev`) — **never `default`**
- **Do not** set `securityContext.allowPrivilegeEscalation: true` or `seccompProfile.type: Unconfined` (backstop policies deny them)
- **No `eks.amazonaws.com/role-arn` annotation** on a ServiceAccount — IRSA is platform-only; an environment annotation is denied (`disallow-irsa-annotation-cross-team`). (Separately, environment AWS access is platform-managed **Pod Identity** (ADR-041): use a **named** ServiceAccount and declare access in the `XEnvironment` claim's deny-set-validated `policyStatements` — a Pod Identity requirement, *not* a Kyverno rejection. See the `environment-onboarding` skill.)
- **Images must be cosign-signed + attested** (keyless; Enforce on preprod). Your app CI is a thin caller of the shared `trusted-ci` build-sign/provenance workflows; trust is registry-derived from `spec.repo`. See the `supply-chain-onboarding` skill.
- **No** `cluster-admin` (Cluster)RoleBindings or wildcard (`*`) verbs/resources in Roles
- **`replicas >= 2` in `*-prod` namespaces** (`require-prod-replica-floor`, ADR-085) — a single replica can't be zero-downtime; an HPA must set `minReplicas >= 2`. **Enforce on preprod + platform** (#934) — a single-replica `*-prod` workload is now rejected at admission; lower stages may stay at 1 for cost. Replicas are validated, never mutated. The New Product scaffolder **emits a default HPA by construction** (ADR-078 Phase 2, "elastic by construction") — its prod overlay sets `minReplicas: 2`, so a scaffolded prod service satisfies this floor without you authoring one; opt out by deleting `k8s/base/hpa.yaml`.

Lower-stakes guidance that won't get a workload rejected — SIGTERM/drain handling (ADR-085), the
recommended-but-not-enforced `app.kubernetes.io/name` label, and regulated-tier (hipaa/pci) extras
(`runAsNonRoot`, `readOnlyRootFilesystem`) — lives in the **`authoring-k8s-workloads`** skill, not
resident here.

If a workload legitimately needs to violate a policy, that's a platform decision — see
`docs/runbooks/kyverno-break-glass.md`; don't weaken a policy to fit one app. A minimal compliant
Deployment lives at `docs/examples/compliant-deployment.yaml` (the New Product scaffolder emits the same
shape automatically).
