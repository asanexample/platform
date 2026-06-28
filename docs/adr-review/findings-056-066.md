# ADR Accuracy Review — ADRs 056–066

Checkout: `/Users/josh/centric/platform-adr-review` (worktree at origin/main).

> Note: project-memory "Argo Rollouts NOT built" is **stale** — the repo shows the `argo-rollouts` module + per-cluster units + Rollout-aware Kyverno present. Trust the repo.

---

## ADR-056: Progressive Delivery & Safe Rollback
- **Status quoted:** `**Status:** Accepted — Phase 1 built + applied (both clusters); Phase 2 mechanics proven (see as-built).`
- **Findings:**
  - [SEVERITY: high] **Canonical index disagrees with the ADR (and the repo).** `docs/adrs/README.md:107` lists ADR-056 as **Proposed**, but the file declares **Accepted — built + applied**, and the repo corroborates the ADR. — **Evidence:** `README.md:107` `| ADR-056 ... | Proposed |` vs file `Status: Accepted`; `infra/modules/argo-rollouts/` + units at `infra/live/aws/{platform,preprod}/us-east-1/platform/argo-rollouts`. — **Proposed fix:** Update the README row to `Accepted` (or a phased status mirroring the ADR header).
  - [SEVERITY: low] "Built" claims corroborated: `argo-rollouts` module + units exist; policy is Rollout-aware via `var.enable_rollout_kind`; dedicated `Rollout` Kyverno test exists. — **Evidence:** `policy/variables.tf:182` (`enable_rollout_kind`), `policy/main.tf:155`, `policy/.kyverno-tests/run.sh:74-79`. — **Proposed fix:** none.
  - [SEVERITY: medium] "applied (both clusters)" / "PROVEN LIVE" not settleable from a static checkout. — **Proposed fix:** none — **NEEDS LIVE/OWNER VERIFICATION** of applied state + the alpha-shop prod canary/auto-rollback (#871–#892).
  - [SEVERITY: medium] **File defect:** stray tool-call XML artifacts (`</content>`, `</invoke>`) leaked into the committed ADR tail (same corruption as ADR-085). — **Proposed fix:** delete the trailer.
- **Decision concerns:** The as-built log accumulates four in-place "CORRECTION to prereq #N" notes; accurate but hard to read as a *decision*. Consider distilling durable conclusions into D-points and moving the blow-by-blow to `docs/plans/056-…`.

## ADR-057: Service Identity & East-West Zero Trust (mTLS)
- **Status quoted:** `**Status:** Proposed — **strategy/direction.**`
- **Findings:**
  - [SEVERITY: low] Status honestly reflects an unbuilt strategy ADR; no present-tense "deployed" claims. Cross-refs (008/017/041/047/049/056) all resolve; Cilium premise matches CLAUDE.md. — **Proposed fix:** none.
- **Decision concerns:** none.

## ADR-058: Per-Cloud Tenant Composition Strategy
- **Status quoted:** `**Status:** Proposed — **strategy/direction** (not implemented). **Vocabulary superseded by [ADR-067]:** the `Tenant`/`XTenant` claim is now `Environment`/`XEnvironment`.`
- **Findings:**
  - [SEVERITY: low] Stale vocabulary is disclosed up-front; body still uses `XTenant` but the banner covers it; multi-cloud scope openly deferred (AWS-only, matches CLAUDE.md). — **Proposed fix:** optional inline "(now `XEnvironment`)".
  - [SEVERITY: low] Reference `../architecture/tenant-api-v2.md` resolves.
- **Decision concerns:** none — appropriately scoped seam decision.

## ADR-059: Identity Topology — Keycloak as the Pluggable Identity Seam
- **Status quoted:** `**Status:** Accepted — **strategy/direction.** ... Builds on the realized B1/B2 work (the `keycloak` + `keycloak-config` modules, the `_teams.hcl` registry).`
- **Findings:**
  - [SEVERITY: medium] **`_teams.hcl` presented as a live, load-bearing source of truth, but it has been retired/removed.** Decision 2 names it the "Access-model SoR … constant in every scenario"; the file is gone (replaced by `gitops/teams/`, ADR-063). A reader would look for a non-existent file with no replacement pointer. — **Evidence:** `059:11,64-71,158`; `_teams.hcl` MISSING; `gitops/teams/{alpha,bravo,platform}.yaml` present; ADR-063 §2. — **Proposed fix:** Add a footnote: "the `_teams.hcl` SoR moved to the git-native `Team` object (`gitops/teams/`) per ADR-063/067."
  - [SEVERITY: low] Module references (`keycloak`, `keycloak-config`) + `scripts/kc-portforward.sh` accurate.
- **Decision concerns:** Seam decision sound; only its concrete SoR artifact drifted.

## ADR-060: Tenant App Hostname Convention — Derive and Inject
- **Status quoted:** `**Status:** Accepted`
- **Findings:**
  - [SEVERITY: medium] **Stale registry path + retired vocabulary, no supersession banner.** Bare `Accepted`; references v2 world in present tense: `gitops/tenant-claims/preprod/<team>.yaml`, the `XTenant` XRD, `Pod-team-<team>`/`DeveloperAccess-<team>`, ECR `team-<team>/<app>`, `charts/tenant/files/composition.yaml`. Claims now live at `gitops/environments/<team>/<product>/<stage>.yaml`; kind is `XEnvironment` (ADR-067). — **Evidence:** `060:11,15,68`; `gitops/tenant-claims` MISSING, `gitops/environments/alpha/shop/{dev,prod}.yaml` present. — **Proposed fix:** Add an ADR-061-style banner: "Vocabulary/paths superseded by ADR-067/069."
  - [SEVERITY: low] Impl-outline names `app-alpha`/`app-bravo` repos + `docs/runbooks/tenant-onboarding.md`; ADR-072 dropped the `app-` prefix and onboarding moved to the skill. — **Proposed fix:** fold into the banner. — **NEEDS OWNER VERIFICATION** of the intended onboarding doc.
- **Decision concerns:** Decision (derive+inject) still in force; staleness is vocabulary/paths. Lowest-effort fix is a banner.

## ADR-061: Tenant Ingress & Custom Domain Strategy
- **Status quoted:** `**Status:** Accepted — strategy/direction. Extends ADR-060. **Refined by ADR-069** …`
- **Findings:**
  - [SEVERITY: low] **Supersession handled correctly** (explicit "Refined by ADR-069"; "`teams.hcl` hostnames are retired" matches repo). Phase 1/2a "shipped" claims plausible and consistent. — **Evidence:** `061:4-8,49,147`; `teams.hcl` MISSING. — **Proposed fix:** optional relabel `XTenant`→`XEnvironment` in the YAML example.
  - [SEVERITY: low] Cilium 1.19.4 premise matches CLAUDE.md; external issue # / Cloudflare pricing unverifiable. — **NEEDS OWNER VERIFICATION**.
  - [SEVERITY: low] Module touch-list all exists.
- **Decision concerns:** none — best-maintained ADR in the batch.

## ADR-062: Self-Service Tenant Provisioning (Backstage + GitOps)
- **Status quoted:** `**Status:** Accepted — built + live (Phase 3, #278–285).`
- **Findings:**
  - [SEVERITY: medium] **Present-tense automerge path points at the retired registry.** §3.4 hard-gates the diff to `gitops/tenant-claims/…`; live path is `gitops/environments/…`. In a "built + live" ADR a stale path in the *security-critical* path-restriction reads as operational fact. — **Evidence:** `062:67`; `gitops/tenant-claims` MISSING, `gitops/environments` present. — **Proposed fix:** Update §3.4 (and §1/§2 "Tenant claim" language) to `gitops/environments/…` / "Environment claim", or add a vocabulary banner.
  - [SEVERITY: low] §4 IAM-escalation-boundary + deprovisioning model consistent with CLAUDE.md/memory. — **NEEDS OWNER VERIFICATION** both `docs/runbooks/{environment,product}-deprovisioning.md` exist.
  - [SEVERITY: low] Scaffolder GitHub-App secret path + read-only/write App split match the `backstage-portal` skill.
- **Decision concerns:** The "Deletion-authorship evolution" reversal ideally gets a dated amendment line for traceability.

## ADR-063: Team as a First-Class Git-Native Object
- **Status quoted:** `**Status:** Accepted — built + live (gitops/teams + github-teams).`
- **Findings:**
  - [SEVERITY: low] **Verified accurate.** `gitops/teams/{alpha,bravo,platform}.yaml` exist; `github-teams` module exists; `_teams.hcl` + app-delivery `teams.hcl` both gone exactly as claimed; the five-unit consumer table consistent with CLAUDE.md. — **Evidence:** filesystem + both HCL registries MISSING. — **Proposed fix:** none.
  - [SEVERITY: low] Body still says "owns N **Tenants**" (pre-067 vocabulary) but predates 067 and is internally consistent. — **Proposed fix:** optional banner.
- **Decision concerns:** none — claims match reality precisely.

## ADR-064: Backstage Provisioning Visibility & Developer Experience
- **Status quoted:** `**Status:** Proposed — design-stage.`
- **Findings:**
  - [SEVERITY: low] Status (Proposed) matches README + design-stage body; no false "built" claims. `XTenant` vocabulary is pre-067 but consistent with Proposed/dated status. — **Proposed fix:** none.
- **Decision concerns:** none.

## ADR-065: Self-Hosted GitHub Actions Runners (ARC) on the Platform Cluster
- **Status quoted:** `**Status:** Accepted — implemented for the platform-cluster increment (2026-06-10). The `platform-infra` runner pool is live and registered (idle at 0).`
- **Findings:**
  - [SEVERITY: high] **Self-contradiction on the deployment mechanism.** The Decision header (`065:101-104`) says ARC is "deployed to the platform EKS cluster **via ArgoCD**." But the chosen-alternative (`065:71-75`), Decision point 1 (`065:108-114`), and Consequences all say **Terragrunt (`helm_release`), not ArgoCD**. Repo + CLAUDE.md confirm Terragrunt. A reader of only the Decision line would hunt for a nonexistent ArgoCD Application. — **Evidence:** `065:102` vs `065:71-75,108,158`; `infra/live/aws/platform/us-east-1/platform/actions-runner-controller/terragrunt.hcl`; no ARC in `gitops/`; CLAUDE.md "applied LOCALLY / via platctl." — **Proposed fix:** Change `065:102` to "deployed via Terragrunt (`helm_release`) — not ArgoCD."
  - [SEVERITY: low] Otherwise highly accurate: Kyverno RBAC-exclusion consequence verified verbatim (`extra_exclude_principals` `system:serviceaccount:arc-systems:*`; `extra_exclude_namespaces` `arc-systems`,`arc-runners`). — **Evidence:** `infra/live/aws/platform/us-east-1/platform/policy/terragrunt.hcl:139-144`.
  - [SEVERITY: low] "live and registered (idle at 0)" — **NEEDS LIVE/OWNER VERIFICATION**.
- **Decision concerns:** The "via ArgoCD" slip undermines the ADR's central "Terragrunt, not ArgoCD, for control-plane" argument; correct promptly.

## ADR-066: SOPS-Encrypted Config Secrets in Git (KMS)
- **Status quoted:** `**Status:** Accepted — built + live (secrets.enc.yaml committed, #338–342)`
- **Findings:**
  - [SEVERITY: low] **Verified accurate end-to-end.** `secrets.enc.yaml` committed; `.sops.yaml` pins KMS key ARN in management (`851725353202`); `common.hcl` decrypts inline via `sops_decrypt_file` with `TG_SOPS_BOOTSTRAP=1` fallback; flat `_secrets.X` accessor real. — **Evidence:** `.sops.yaml`; `infra/live/aws/common.hcl:11`. — **Proposed fix:** none.
  - [SEVERITY: low] §2 attributes the decrypt to `common.hcl` — correct (CLAUDE.md's "root.hcl/common.hcl" is the looser statement). — **Evidence:** `grep sops_decrypt_file` matches only `common.hcl`.
- **Decision concerns:** none — model ADR.

---

## Cross-cutting note

1. **The canonical index drifts from the ADRs.** ADR-056 is `Accepted` in-file (repo-corroborated) but `Proposed` in `README.md:107`. High-value reconcile. (Project-memory "Rollouts NOT built" is itself stale — trust the repo.)
2. **v2→v3 vocabulary/path drift is uneven.** ADR-061/063 handle the `Tenant`/`XTenant`/`teams.hcl` → `Environment`/`XEnvironment`/`gitops/teams` transition cleanly; ADR-059/060/062 still reference retired artifacts in present tense — most consequentially ADR-062 §3.4's security gate and ADR-060's claim paths point at the nonexistent `gitops/tenant-claims`. A short banner on 059/060/062 (061's style) resolves all without body rewrites. Standout single error: ADR-065's Decision-line "via ArgoCD".
