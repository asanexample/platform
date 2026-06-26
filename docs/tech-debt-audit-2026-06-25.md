# Technical Debt Inventory — Platform IaC Repo

**Date:** 2026-06-25
**Branch audited:** `worktree-tech-debt-audit` (≡ `feat/ruler-rules-sync`, at commit `98009875`)
**Scope:** Entire repository — 1,068 tracked files (244 `.tf`, 172 `.yaml`, 115 `.hcl`, 45 `.sh`, 42 `.go`, 337 `.md`, 83 ADRs, ~64 modules).
**Method:** Ten parallel adversarial audit passes across distinct dimensions (modules, live units, testing, CI/CD, docs/ADRs, debt markers/dead code, k8s/gitops/policy/crossplane, Go/shell code, security/IAM, version pinning). Findings below are deduped and cross-referenced; items that independently surfaced in multiple passes are flagged **⨯N confirmed** and carry the highest confidence.

> This is an **inventory for later prioritization**, not a change set. Nothing here was fixed. Severities are the auditors' assessment; re-triage before scheduling. IDs (`TD-NNN`) are stable handles for tracking.

---

## 1. Executive Summary

The codebase is, on the whole, **well-tended**: near-zero inline `TODO/FIXME/HACK` markers in code, no committed plaintext secrets, no provider blocks in modules, consistent house style in most modules, genuinely high-quality (where present) Terratest + render harnesses, a mature and well-hardened `pull_request_target` CI gate, and a sound SOPS/KMS secrets design. The debt that exists is **structural and systemic**, not sloppiness — it clusters into a small number of recurring themes that are worth tackling as themes rather than one-off tickets.

**The five dominant themes (each spans many files and several audit passes):**

1. **Version-pinning fragmentation & drift** — the `.tool-versions` "single source of truth" is bypassed in several places; provider constraints are inconsistent across ~24 modules (`>= 2.0` … `>= 3.0`); 28 Helm chart pins likely have *zero* automated update coverage; Go is pinned in three different places and not in `.tool-versions` at all.
2. **Stale multi-cloud (Azure) carcass** — the repo went AWS-only, but the `Makefile`, several scripts, a test README, and a region scaffolder are still Azure-era and **broken**.
3. **Self-admitted regressions left open** — chiefly **#647** (the per-team `DeveloperAccess` path is non-functional end-to-end), surfaced by 4 independent passes; plus Kyverno-webhook unpark wedge (#665), Falco alerts going nowhere, and the CMK-deferral backlog (#118).
4. **Admission/supply-chain enforcement asymmetry** — cosign image/attestation verification is **Audit-only (effectively off)** on the platform/hub cluster where the first live agent runs, while preprod enforces it.
5. **Test & enforcement signal decoupled from change** — ~92% of modules have no tests; the few that exist run weekly-only (never gate PRs), platctl's 2,800-line test suite never runs in CI, and `make test` is dead.

Plus a sixth, lower-stakes-but-pervasive theme: **hardcoded values that bypass existing single-source mechanisms** (base domain ×25, org name ×8, account IDs) and **ADR status drift** (the entire built-and-live v3 domain model is still marked "Proposed").

**Aggregate finding count:** ~150 findings across the 10 passes, roughly **18 High, ~55 Medium, ~75 Low** (before dedup; the cross-cutting section collapses the High/Med overlaps).

---

## 2. Cross-Cutting Themes (highest priority — multi-pass confirmed)

These are the items that independently appeared in more than one audit pass. They are the highest-confidence, highest-leverage work.

### TD-001 — Per-team DeveloperAccess path is non-functional end-to-end (regression #647) — **HIGH** ⨯4 confirmed

The v3 Crossplane Composition emits only the in-cluster `environment-developers` RoleBinding (`infra/modules/crossplane/charts/environment-api/files/composition.yaml:274-292`) — **no** EKS AccessEntry and **no** `DeveloperAccess-<team>` IAM role. So the RoleBinding binds a group nobody can assume; ADR-039 namespace-scoped developer kubectl is a documented capability that does not exist. Compounding it: `identity-center` grants `sts:AssumeRole` on these non-existent roles (`mgmt/global/identity-center/terragrunt.hcl:55,84`), and the platform EKS access entry for it is commented out (`platform/.../eks/terragrunt.hcl:72-77`). Net: the only working operator path is PlatformAdmin / `platctl kubeconfig`, pushing users to broader roles than intended.
*Surfaced by: security, k8s/crossplane, terragrunt, docs, markers passes.*

### TD-002 — Provider version constraints are fragmented & unbounded across ~24 modules — **HIGH** ⨯2 confirmed

- **AWS provider:** three patterns coexist — `>= 5.0` (15 modules), `>= 6.0` (3), `~> 6.0` (6). The `>=` modules have no upper bound and will silently jump to AWS provider 7.x on release.
- **Kubernetes provider:** four levels — `>= 2.0` (argocd, backstage, actions-runner-controller, keycloak), `>= 2.10.0` (cluster-rbac, vcluster), `>= 2.35.0` (15), `>= 3.0` (argocd-apps). The `>= 2.0` modules span a 3-major range and the k8s provider 3.0 had breaking changes — a live upgrade hazard.
- **Helm provider:** `falco/versions.tf:7` is the lone `>= 2.0` outlier (everyone else `>= 3.0`).
- ~38 modules use bare `>=` with no `~>` ceiling, against the house version-range-pinning style.
*Recommend standardizing on `~> 6.0` (aws) / `~> 2.35` (k8s) / `~> 3.0` (helm) fleet-wide. Surfaced by: modules, version passes.*

### TD-003 — Go toolchain version drift; Go absent from `.tool-versions` — **HIGH** ⨯3 confirmed

Three Go directives in-repo: `cmd/platctl/go.mod` = `1.24.3`, `infra/tests/aws/go.mod` = `1.26.2`, `scaffolder/.../skeleton-go/go.mod` = `1.24`. CI is worse: `test-aws.yml` pins `GO_VERSION: "1.22"` — **4 minors behind** the module it builds (`1.26.2`), working only because setup-go auto-downloads the toolchain and masks the drift. `ci.yml` uses floating `go-version: stable`. `.tool-versions` (the SSOT) pins the five CLI tools but **not Go**, despite three Go modules.
*Surfaced by: testing, go-code, version passes.*

### TD-004 — Stale Azure-era artifacts, several actively broken — **HIGH** ⨯3 confirmed

The repo is AWS-only, but these remain and are broken/misleading:

- **`Makefile` top half** (`:1-271`): `CLOUD ?= azure`, `REGION ?= eastus`, hard-pinned `TERRAFORM_VERSION 1.6.0`/`TERRAGRUNT_VERSION 0.53.0` (contradicting `.tool-versions`), `init/plan/apply/destroy/validate/test` all depend on `check-azure-auth`, use deprecated `terragrunt run-all` (v0.x CLI), `terraform` not `tofu`, and `make test` targets a non-existent `infra/tests/modules/$(CLOUD)` path with `*.tftest.hcl` (repo uses Terratest/Go). The headline dev commands are broken.
- **`infra/tests/README.md`** — entirely describes Azure modules, Key Vault, `azurerm`, native `.tftest.hcl` framework; actively misleads contributors.
- **`scripts/migrate-state-to-workload-hierarchy.sh`** — migrates state in *Azure Blob Storage*; unrunnable.
- **`infra/scripts/scaffold_region.sh`** — multi-cloud region scaffolder sourcing from `infra/live/{cloud}/_templates/region`, **a directory that does not exist** → dead/broken.
- **`infra/tests/provider_local.tf.template`** — orphaned Azure provider template.
- Latent (intentional, cloud-agnostic): `cilium` module + `cmd/platctl` engine still carry azure/gcp branches.
*Surfaced by: CI, markers, go-code, testing passes.*

### TD-005 — GitHub Actions are not SHA-pinned anywhere in this repo's own workflows — **HIGH** ⨯2 confirmed

Every `uses:` in `.github/workflows/*` is a floating major tag (`actions/checkout@v7`, `aws-actions/configure-aws-credentials@v6`, `docker/build-push-action@v7`, `sigstore/cosign-installer@v3`, …), **including inside the security-critical `pull_request_target` gates** (`gitops-gate.yml:83,104`). This is the repo's sharpest internal inconsistency: the platform is a supply-chain *showcase* (it cosign-signs images, SHA-256-verifies CLI installs, documents the `tj-actions`/`trivy-action` tag-hijack class as motivation, and *forces tenants* to pin reusable workflows to full SHAs) — yet rides mutable tags itself. Dependabot can maintain SHA pins with version comments.
*Surfaced by: CI, version passes.*

### TD-006 — Cosign verify/attest is Audit-only (effectively off) on the platform/hub cluster — **HIGH** ⨯2 confirmed

`platform/.../policy/terragrunt.hcl` sets `verify_subjects_product` (now non-empty — the live `triage-copilot` agent) but never sets `enable_image_verification` / `enable_attestation_verification` / `verify_failure_action` / `attest_failure_action`. Module defaults are `false`/`Audit`, and the templates render nothing when `enableImageVerification` is false. **Net: the platform's first live agent runs on the hub with no signature/attestation verification at all** — not even Audit — despite the unit comment claiming it "lands the agent's image-signing guarantee on the hub." preprod correctly Enforces. Real supply-chain gap, not just an Audit→Enforce flip.
*Surfaced by: k8s/crossplane, security passes.*

### TD-007 — `set -uo pipefail` without `-e` in security-critical CI gate scripts — **MEDIUM** ⨯2 confirmed

Several merge-gate/validator scripts (`gitops-gate/validate-releases.sh`, `teams/gate.sh`, `registry/apply.sh`, `ci/validate-modules.sh`) run `set -uo pipefail` **without `-e`**. `ci.yml:139-141` itself documents that a `classify-diff` `set -e` regression once "slipped through." Without fail-fast, an unhandled command failure mid-gate continues and risks a **false-green verdict** on prod/release-approver gating. (The best-effort sweep scripts omit `-e` deliberately — those are fine; the gate/validator scripts should fail-closed.)
**[Verified 2026-06-25]** Not uniform: `gitops-gate/validate-deletions.sh` and `scripts/lib/common.sh` *already* use `set -euo pipefail` — so the deletion gate is fine and the finding is narrower than "all gate scripts." Audit each gate/validator individually rather than blanket-applying `-e`.
*Surfaced by: CI, go-code passes.*

### TD-008 — Deprecated `teardown-platform.sh` retained, hardcoded, divergent from platctl — **MEDIUM** ⨯3 confirmed

`scripts/teardown-platform.sh:3` is explicitly marked `DEPRECATED … no longer maintained`, yet 157 lines remain, reimplementing the teardown DAG that `platctl` now owns — with hardcoded `CLUSTER_NAME`/`REGION`/unit paths, a blind `sleep 300`, and its own destroy ordering that won't track `.platctl.yaml`. Still advertised as "legacy" in `docs/user-guide.md:344`. Its sole-purpose helper `scripts/lib/common.sh` is sourced nowhere else. Will silently rot out of sync with the real ordering and mislead operators.
*Surfaced by: markers, go-code, CI passes.*

### TD-009 — Hardcoded values that bypass existing single-source mechanisms — **MEDIUM** ⨯2 confirmed

- **Base domain** `aws.refplat.org` / `preprod.aws.refplat.org` hardcoded in ~25 units (gateway, external-dns, route53, observability, keycloak, argocd, backstage, all preprod spokes) — no `base_domain` local exists.
- **Org name** `"asanexample"` hardcoded in ~8 units despite `common.hcl:39` defining `org_name` with a "Change here to rebrand" comment that nothing consumes.
- **Platform account ID** baked into a module default (`backstage/variables.tf:55`) and an ARC unit literal (`actions-runner-controller/terragrunt.hcl:103`), instead of `include.base.locals.account_id` / SOPS.
*A rebrand/region migration currently means editing dozens of files. Surfaced by: terragrunt, modules passes.*

### TD-010 — ADR status drift: the entire built-and-live v3 model is still "Proposed" — **HIGH** (docs)

The "Proposed" label systematically lags reality across the whole v3 cluster — **ADR-062, 063, 066, 067, 069** are all built and live (registries, XEnvironment XRD/Composition, SOPS secrets, registry-derived delivery) yet still marked not-built; CLAUDE.md cites them as authoritative current state. Plus **ADR-072 is entirely missing from the canonical ADR index**, and **ADR-082 (newest, Accepted) has three broken cross-reference links** to renamed files. ADR-080 (triage agent) is "Proposed" while the agent is live.
*Surfaced by: docs pass.*

---

## 3. Full Inventory by Domain

### 3.1 OpenTofu Modules (`infra/modules/`)

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-101 | High | **18 of 23 `aws/*` modules have no `versions.tf`/`required_providers`** — core resource modules (eks, networking, iam_roles, organizations, s3, state_bootstrap, …) silently inherit whatever the unit resolves; no guard against an aws-provider major bump. | `infra/modules/aws/*` |
| TD-102 | Med | **S3-backend + Pod-Identity IAM block copy-pasted ×4** (~320 dup lines) — mimir/loki/tempo/pyroscope each replicate identical bucket+encryption+lifecycle+IAM+pod-identity; a baseline change must be hand-applied 4× and will drift. Candidate `observability-s3-backend` submodule. | `observability-{mimir,loki,tempo,pyroscope}/main.tf` |
| TD-103 | Med | **Variable validation coverage ~3%** — 25 validation blocks across 854 variables; ARNs/account-IDs/CIDRs/versions accept any string, pushing failures from plan to apply. | repo-wide `variables.tf` |
| TD-104 | Med | **Cilium Gateway-API CRDs fetched from a GitHub release URL at apply** (unverified, **experimental** channel) — breaks airgapped applies; supply-chain ingress. | `cilium/main.tf:193-196` |
| TD-105 | Med | **`null_resource` + `local-exec` provisioners across 6 modules** (crossplane orphan sweeps, cilium CRD install, tailscale/keycloak/observability/backstage finalizer cleanup) — host-dependent, unauditable by plan, fail silently, untestable. | crossplane, cilium, tailscale, keycloak, observability, backstage |
| TD-106 | Low | **`replace = true` on 10 helm_releases** as a "stuck FAILED" crutch — on stateful charts (cloudnative-pg, keycloak) a delete+recreate is a latent disruption risk. | 10 modules |
| TD-107 | Low | **Zero `moved {}` blocks** anywhere despite in-flight renames (tenant→environment, `_v1` #59) — future refactors force destroy+recreate. | all modules |
| TD-108 | Low | Modules missing `outputs.tf` (argocd-apps, observability-blackbox/k6/pyroscope-ebpf); main.tf files lacking `# ---` section banners (aws/iam_roles, aws/identity_center, aws/sops-kms, observability-beyla); large inline-config modules (observability/main.tf 844 lines, crossplane/main.tf ~700). | various |
| TD-109 | Low | `arn:aws:` partition assumed everywhere (no `data.aws_partition`) — latent GovCloud/China debt. | IAM resources repo-wide |

### 3.2 Terragrunt Live Units (`infra/live/`)

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-201 | High | **`organizations` dependency missing `mock_outputs`** (only such case in the tree) — breaks `destroy`/validate of identity-center when org state is absent (house-rule violation). | `mgmt/global/identity-center/terragrunt.hcl:14-16` |
| TD-202 | High | **identity-center hand-maintains per-team SSO data, points at the RETIRED `teams.hcl`**, grants assume-role to the non-existent DeveloperAccess roles (TD-001), and commits placeholder sample users/emails as live config. Should derive from `gitops/` registries like policy/github-oidc/argocd-apps already do. | `mgmt/global/identity-center/terragrunt.hcl:39-153` |
| TD-203 | Med | **helm/kubernetes provider `generate` blocks duplicated ~91×** (59 helm + 32 k8s, byte-identical) — a change to exec-auth means editing ~91 sites. Candidate `_envcommon` generate include. | cluster add-on units |
| TD-204 | Med | Mixed pinning in `root.hcl` generated `versions.tf`: `aws = 6.47.0` exact but `helm`/`kubernetes` floating `>=` → non-reproducible provider resolution. | `infra/root.hcl:35-43` |
| TD-205 | Low-Med | Env-tag plumbing duplicated across all 5 `env.hcl` + `common.hcl`; `secret-stores`/`cilium`/`cluster-rbac` units byte-identical across platform & preprod (no `_envcommon` → silent drift). | `*/env.hcl`, paired units |
| TD-206 | Low | Dead/vestigial tag plumbing in `root.hcl` (`common_tags` input declared by no module; `locals.common_tags` unreferenced) — two parallel tag mechanisms, one dead. | `infra/root.hcl:71-114` |
| TD-207 | Low | Commented-out dead blocks referencing pre-ADR-067 model: `developer` access entry with `namespaces=["team-a"]` (eks units); `preprod_dns` dependency with a non-resolving `config_path`. | eks, cross-vpc-dns units |
| TD-208 | Low | `prod/` (lone orphaned VPC, costs NAT for nothing) and `test/` (only iam-roles + github-oidc) are partial stubs; the prod VPC is dead infra until the rest lands. | `infra/live/aws/{prod,test}` |

### 3.3 Testing

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-301 | High | **Terratest module tests never gate PRs** — `test-aws.yml` triggers only `workflow_dispatch` + weekly schedule; a breaking module change merges green, caught up to 7 days later. | `.github/workflows/test-aws.yml` |
| TD-302 | High | **platctl's 2,825 lines of Go tests never run in CI** — `make test-platctl` exists but no workflow invokes it; the orchestrator most able to cause a destructive mistake has tests no gate enforces. | `cmd/platctl/internal/**/*_test.go` |
| TD-303 | High | **`make test`/`test-module`/`test-category` are dead** — point at non-existent `infra/tests/modules/$(CLOUD)`, depend on removed Azure auth, glob `*.tftest.hcl`, call `terraform test` (repo is Terratest/Go + tofu). (Same root as TD-004.) | `Makefile:23,131-144` |
| TD-304 | Med | **~59 of ~64 modules have zero tests** — untested high-blast-radius modules include `iam_roles`, `organizations`, `state_bootstrap`, `eks-addons`, `karpenter`, `github_oidc`, `argocd*`, and all 17 `observability*`. (Only eks/networking/ssm-bastion Terratest; policy/crossplane have render harnesses.) | repo-wide |
| TD-305 | Med | **ssm-bastion Terratest exists but is wired into no workflow**; gate-script test gaps (`classify-diff.sh`, `validate-products.sh`, `render-environments.sh` untested; entire `teams/` gate untested though `ci.yml:153` implies otherwise); `scripts/` operational scripts (incl. destructive teardown/sweeps/state-migration) have no tests. | tests + `.github/scripts` |
| TD-306 | Low | Go-version sprawl (5 different stances — see TD-003); some module behaviors asserted plan-only (eks addons / group-mapped access entry). | various |

### 3.4 CI/CD, Scaffolder, Scripts, Docker

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-401 | Med | **Stale base-image/language versions in scaffolder skeletons** — `golang:1.24-alpine` + `go 1.24` (app repos already on Go 1.26 → golden path lags the live fleet), `python:3.11`, `ruby:3.3`, `rust:1`. New products scaffolded already-stale. | `scaffolder/.../skeleton-*/Dockerfile` |
| TD-402 | Med | **Skeleton Dockerfiles use floating base tags, not digests** (incl. mutable `distroless:nonroot`); ruby skeleton runtime is non-distroless `ruby:3.3-slim` (off-pattern vs the other 5). Inconsistent with the platform's digest-pinned deployed-image posture. | skeleton Dockerfiles |
| TD-403 | Med | **`actionlint.yaml` config is orphaned** — declares the self-hosted runner label but no workflow/Makefile/hook invokes actionlint. | `.github/actionlint.yaml` |
| TD-404 | Low | Split trusted-ci SHA pins within one skeleton (`build-sign.yml@7a739dc` vs `promote.yml@28dbe1b6`) — drift smell, inherited by every scaffolded product; checkout `@v6` vs `@v7` drift between repo and skeleton. | skeleton workflows |
| TD-405 | Low | AWS CLI v2 installed without GPG signature verification (the one unverified tool in an otherwise SHA-256-verified runner Dockerfile) — known TODO. | `docker/gha-runner/Dockerfile:72-73` |
| TD-406 | Low | terraform-docs README drift is not CI-enforced (only the opt-in pre-commit hook regenerates it, and the hook silently `git add`s mid-commit); pre-commit lints no Go (`gofmt`/`vet`) or shell (`shellcheck`). | `.githooks/pre-commit`, Makefile |

### 3.5 Documentation & ADRs

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-501 | High | **ADR status drift** — ADR-062/063/066/067/069 all built+live but marked "Proposed" (CLAUDE.md treats them as authoritative); ADR-080 "Proposed" while agent is live. (See TD-010.) | `docs/adrs/*` |
| TD-502 | High | **ADR-072 missing from the canonical ADR index**; **ADR-082 has 3 broken cross-ref links** (014/041/047 filenames wrong) in the newest reader-facing ADR. | `docs/adrs/README.md`, `082-*.md` |
| TD-503 | Med | Broken renamed-runbook link (`kyverno-shift-left.md` → non-existent `tenant-claims-automerge.md`, renamed to `gitops-gate-automerge.md`); ROADMAP lists Karpenter Phase 1 "in progress" though shipped+live (body contradicts its own changelog). | docs/architecture, ROADMAP |
| TD-504 | Low | Retired "Tenant" vocabulary in Accepted ADR-046/048 status lines; `app-` prefix referenced as current in `deploy-app-preprod.md`; two near-identical deprovisioning runbooks (env vs product) duplicate the same mechanism → drift risk; in-doc durable-fix TODOs in rebuild runbook. | various docs |

Positive — all 63 module dirs have non-stub READMEs; REQUIREMENTS.md and legacy docs are clearly banner-flagged.

### 3.6 Kubernetes / GitOps / Policy / Crossplane

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-601 | High | Hub agent cosign verify/attest is **inert** (master switch off) — see TD-006. | `platform/.../policy/terragrunt.hcl` |
| TD-602 | Low | **Defensive-validation gap: per-service resources are silently dropped if `serviceAccount` is omitted** — the entire per-service block (Pod-Identity + S3/SQS/SNS/DynamoDB MRs) is gated on `if $svccfg.serviceAccount` with no error surfaced when a service declares resources but no SA. **[Verified 2026-06-25 — downgraded]** The originally-cited instance is a *ghost*: `alpha/conformance/dev.yaml:14` *does* set `serviceAccount: app-alpha`, so its 4 resources provision correctly. No broken instance exists today; this is a latent hardening gap (XRD/Gate should reject resources-without-SA), not an active bug. | `composition.yaml:375,436` |
| TD-603 | Med | **Environment-envelope ClusterPolicies default to `Audit`** (only preprod overrides to Enforce) — any new env-api install relying on defaults runs envelope rules audit-only. | `crossplane/charts/environment-policies/values.yaml:9` |
| TD-604 | Med | **Composition is 916 lines of dense go-templating** (inline IAM JSON, per-engine ARN computation, repeated truncate-and-hash) — hard to review/test, with a known cascade-delete hazard on in-place XRD edits; only safety net is the offline render harness. | `composition.yaml` |
| TD-605 | Med | **`part-of` label taxonomy drift** — Team CRs labeled `tenant-api`, Products/Environments labeled `environment-api` (ADR-067 retired "Tenant") → breaks any catalog/selector grouping by `part-of`. | `gitops/teams/*.yaml` |
| TD-606 | Med | **Release `platform-triage-copilot-dev` references a non-existent XEnvironment** (agent uses `XAgent`; no `gitops/environments/platform/` tree) — dangling ref, acknowledged follow-up. | `gitops/releases/platform/triage-copilot/dev.yaml` |
| TD-607 | Low | Crossplane provider/function/util images pinned by mutable tag, not digest; conformance env missing the sibling header block; `serviceAccount: app-alpha` retains the dropped `app-` prefix; single-active-Release relies on ArgoCD name-collision rather than an explicit guard. | crossplane charts/units, gitops |

Positive — AppProjects are well-scoped, selfHeal+prune on everywhere, no wildcard RBAC / cluster-admin bindings, NetworkPolicies tight, no literal account IDs/ARNs in the Composition.

### 3.7 Go & Shell Code

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-701 | High | **No graceful signal handling in the orchestrator** — `main.go:36` uses `root.Execute()` not `ExecuteContext`+`signal.NotifyContext`; bootstrap/teardown contexts resolve to `context.Background()`. Ctrl-C during a multi-hour run hard-kills mid-`terragrunt`, defeating the engine's resumable, state-tracked DAG on the one event (operator abort) that needs it most. | `cmd/platctl/main.go:36`, bootstrap.go:279, teardown.go:242 |
| TD-702 | Med | **Silently-ignored errors on state/log persistence** (`engine.go:228` `_ = e.Store.Save(...)`) undermine resume reliability — a failed save is swallowed, so `--resume` silently replays/over-runs. | `engine/engine.go:148,228` |
| TD-703 | Med | **`platctl teardown` has no top-level destroy confirmation** + dead `--yes` Phase-3 stub (`teardown.go:157`); the deprecated shell script it replaced *did* prompt `Type DESTROY`. Full-env destroy relies on incidental hook prompts. | `cli/teardown.go:157` |
| TD-704 | Med | Deprecated AWS SDK **v1** in the test module (maintenance-only); stale/duplicated indirect deps in `cmd/platctl/go.mod` (`go-textseg` v13 *and* v15; `x/sys v0.5.0` vs v0.45.0, etc.); anomalous `terratest v1.0.0` pin to verify; duplicated validation lists for hook/check names (`config.go` vs `hooks.go`) drift-prone. | go.mod files, config/ |
| TD-705 | Med | **`scale.go` AWS shell-outs lack context cancellation** (`exec.Command` not `CommandContext`) and use scattered magic retry constants (`i<90`, `i<36`, `i<12`); Kyverno fail-closed webhook can wedge all policed pods post-unpark (#665), mitigated only best-effort. | `cli/scale.go` |
| TD-706 | Med | **`scaffold_region.sh` uses `eval` for dynamic var assignment** on CSV-file-derived content (injection/quoting hazard; namerefs are the safe idiom) + brittle positional `grep|cut` CSV parsing. (Also dead per TD-004.) | `infra/scripts/scaffold_region.sh:240,257,404` |
| TD-707 | Low | Dead Azure branch (`runner.go:171`); no-op leftover loops in `graph.go:136-147`; unused `RunError.LogPath` field; full subprocess output buffered in memory for the whole run (no streaming). | engine/ |
| TD-708 | Low | Shell hygiene: hardcoded `us-east-1`/secret-names/paths in `lib/common.sh`; unquoted expansions (`eks-tunnel.sh:55`, `for x in $(aws … --output text)` pattern); irreversible force-deletes in sweeps (`ecr delete-repository --force`, `delete --force --grace-period=0`) — filtered/teardown-scoped but unguarded. | scripts/ |

*(Positive: Go builds clean, no TODO/panic/commented-out code in non-test Go, errors wrapped with `%w`, injectable command boundaries, shell-injection guard `isSafeAccountName`, admin password via stdin.)*

### 3.8 Security & IAM

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-801 | High | **EKS module defaults to a fully public, world-open API endpoint** — `endpoint_public_access = true`, `public_access_cidrs = ["0.0.0.0/0"]`. Live units override to private, but the secure posture depends on every caller remembering; contradicts the private-only house rule (ADR-010). Flip the default to private-only. | `aws/eks/variables.tf:35-45` |
| TD-802 | Med | **platctl bootstrap opens the public endpoint to 0.0.0.0/0**, re-closing only in a later "Lockdown" phase after all units succeed — an aborted/interrupted bootstrap leaves the API publicly exposed until `--resume` re-runs lockdown; the window also uses the wide-open default CIDR. | `.platctl.yaml.example:73-76`, `cli/bootstrap.go:284-296` |
| TD-803 | Med | **Break-glass `OrganizationAccountAccessRole` wired as a STANDING cluster-admin EKS access entry** on both clusters (`AmazonEKSClusterAdminPolicy`) — "break-glass only" per docs, but provisioned as always-on admin that bypasses the GitOps-only authoring model. | platform/preprod eks units |
| TD-804 | Med | Hub cosign verify/attest Audit-only (TD-006); per-Product ECR-push OIDC role trusts the `pull_request` event **and** can read the promote GitHub-App secret (`secretsmanager:GetSecretValue` on `platform/promote/github-app-*`) — a sharp trust edge. | github-oidc units |
| TD-805 | Low | **No IAM permission boundaries anywhere** (iam_roles/github_oidc support none) — high-value roles (PlatformDeployer) have no max-privilege backstop; residual justified wildcard `Resource:"*"` to keep watching; test-account Terratest OIDC = AdministratorAccess from `feat/*` (acknowledged, env-gate follow-up pending); ArgoCD runs TLS-off by default (`server_insecure = true`). | iam modules, argocd |

*(Positive: no committed plaintext secrets; SOPS/KMS design sound — `prevent_destroy`, rotation, ArnLike conditions, decrypt-only runner; non-leaky outputs; S3/CloudTrail/EKS encryption on; all `0.0.0.0/0` rules are egress-only.)*

### 3.9 Version Pinning & Dependency Automation

| ID | Sev | Finding | Location |
|----|-----|---------|----------|
| TD-901 | High | **`test-aws.yml` hardcodes `TOFU_VERSION: "1.12.1"`** instead of reading `.tool-versions` — exactly the second-place pin the SSOT design exists to prevent; a `.tool-versions` bump silently leaves Terratest CI on the old version. (Plus TD-003 Go drift.) | `.github/workflows/test-aws.yml:16` |
| TD-902 | Med | **28 Helm chart pins likely have ZERO automated update coverage** — Dependabot `terraform` updater tracks `required_providers`/module sources, not `helm_release version = "x.y.z"` literals; no `docker` ecosystem declared for the root repo (only the scaffolder template has it). The stack's most numerous pins are unmanaged. | `.github/dependabot.yml`, `_versions.hcl` |
| TD-903 | Med | **Must-manually-sync version pairs** (each = drift-debt): kubectl/cluster minor pinned in 3 places (`.tool-versions` ↔ eks `kubernetes_version` ↔ crossplane kubectl image); `CROSSPLANE_VERSION v2.2.1` ×3 workflow spots; `cosign v2.5.2` / `SYFT 1.44.0` cross-repo; Kyverno appVersion ↔ chart; 24 chart defaults ↔ `_versions.hcl`. | ci.yml, gitops-gate.yml, modules |
| TD-904 | Med | **crank CLI (v2.2.1) lags the deployed Crossplane chart (2.3.1)** — CI validates/renders the Environment API against an older Crossplane than production (CEL/XRD behavior can differ). | ci.yml, gitops-gate.yml |
| TD-905 | Med | otel-collector overrides image `repository` with no `tag` (resolves via chart appVersion — floats if upstream renames); EKS managed add-on versions unpinned (`addon_version` optional, no default/override → floating, account/time-dependent). | observability-otel-collector, aws/eks-addons |
| TD-906 | Med | Chart versions duplicated as module `variables.tf` defaults (24 modules) — dormant but latent drift; 7 chart modules conversely have *no* default (no fallback/record). Pick one convention. | modules |
| TD-907 | Low | Inline-pinned CI tool versions scattered outside `.tool-versions` (TRIVY 0.70.0, semgrep 1.164.0, yq 4.44.3, etc.); `config-hierarchy.md:119` cites AWS provider `6.47.0` that doesn't exist as a pin in code; chart staleness to track (external-secrets 0.14.3, loki 7.0.0, cert-manager 1.17.1). | ci.yml, docs, _versions.hcl |

### 3.10 Open Regressions & Deferred-Hardening Backlog (issue-referenced)

| ID | Sev | Finding | Ref |
|----|-----|---------|-----|
| TD-1001 | High | DeveloperAccess path non-functional (TD-001). | #647 |
| TD-1002 | Med | Kyverno fail-closed webhook wedges workloads post-unpark (0 pods until Kyverno restarted); best-effort `recoverKyverno` only. | #665 |
| TD-1003 | Med | **Falco detections only go to stdout** — SNS/Slack/#102 routing not built; runtime threat detections go nowhere actionable. | ADR-045 |
| TD-1004 | Med | Customer-managed CMK deferred (SNS, state buckets, CloudTrail) — 9 standing `.trivyignore` suppressions; accepted-risk hardening backlog. | #118 |
| TD-1005 | Low | CI permanently skips `tofu validate` on `argocd` + `vcluster` ("known provider compatibility issues"); vcluster also deferred (ADR-033) yet carried. | validate-modules.sh:42 |
| TD-1006 | Low | IRSA→Pod-Identity TagSession trust regression (#677) — already fixed in place, comment now historical; EBS CSI addon left on IRSA (per CLAUDE.md). | #677, #594 |

---

## 4. Suggested Prioritization (for later triage)

**Tier 1 — fix soon (security/correctness, spot-verified 2026-06-25):**
TD-001/1001 (#647 dev access ✓), TD-006/601/804 (hub cosign Audit-only ✓), TD-801 (EKS public default ✓), TD-007 (gate-script `set -e` — ✓ but narrower than first stated).
*(TD-602 was in the original Tier-1 draft but verification demoted it to Low — no active bug.)*

**Tier 2 — systemic hygiene (do as themes, high leverage):**
TD-002 (provider constraints), TD-003/901 (Go + tofu version SSOT), TD-004 (delete the Azure carcass), TD-005 (SHA-pin Actions), TD-902 (Helm/Dependabot coverage), TD-301/302 (wire tests into PR gates).

**Tier 3 — refactor debt (schedule opportunistically):**
TD-101 (module versions.tf), TD-102/203 (de-dup S3 backend + provider generate), TD-009/202 (hardcoded domain/org + identity-center registry-ize), TD-604 (Composition complexity), TD-701 (signal handling).

**Tier 4 — cleanup/docs (low risk, low effort):**
TD-008 (delete deprecated teardown), TD-010/501/502 (ADR status + index + links), TD-206/207/208 (dead live-unit cruft), TD-303/Makefile.

---

## 5. What's Healthy (explicitly checked, no debt)

- Near-zero inline `TODO/FIXME/HACK` in code (4 TODOs total, none in module code); no commented-out code blocks; no `.bak`/`_old`/`_v1` files; no stuck `count=0`/`enabled=false` toggles.
- No committed plaintext secrets; SOPS/KMS design is sound; no secret values leak through outputs.
- No provider blocks in modules; `TerraformBinary: "tofu"` set in all test suites; least-privilege CI `permissions:` with justifications; well-hardened `pull_request_target` gates.
- All 63 module dirs have non-stub READMEs; legacy docs are clearly banner-flagged.
- No wildcard RBAC / cluster-admin bindings in platform charts; AppProjects scoped; all `0.0.0.0/0` rules egress-only.
- Where tests exist, they're high quality (real apply + AWS-API assertions; offline render harnesses for policy/crossplane; extensive platctl unit tests with injectable command boundaries).

---

*Generated by a 10-agent parallel audit on 2026-06-25. Re-validate each finding against current `main` before acting — some live-unit overrides already mitigate module-default risks (noted inline).*
