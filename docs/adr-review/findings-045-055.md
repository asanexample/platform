# ADR Accuracy Review — ADRs 045–055

Checkout: `/Users/josh/centric/platform-adr-review` (worktree at origin/main).

---

## ADR-045: Falco for Runtime Threat Detection
- **Status quoted:** `Accepted — deployed on the **preprod** cluster (modern eBPF), platform #116 / PR #134.`
- **Findings:**
  - [SEVERITY: low] Status and body claims verify out. The `falco` module exists with `driver_kind` variable defaulting to `modern_ebpf` exactly as stated. — **Evidence:** `infra/modules/falco/variables.tf:25-28` (default `"modern_ebpf"`); live unit only at `infra/live/aws/preprod/us-east-1/platform/falco` (preprod-only matches "platform cluster not yet covered"). — **Proposed fix:** none.
  - [SEVERITY: low] "the `sns-notifications` module already names Falco as a publisher" — verified correct. — **Evidence:** `infra/modules/aws/sns-notifications/variables.tf:8`, `README.md:4,31`, `main.tf:4-5`. — **Proposed fix:** none.
- **Decision concerns:** none. Well-scoped, honest about the preprod-only gap and unwired alerting.

## ADR-046: Adopt the BACK Stack for Developer Self-Service
- **Status quoted:** `Accepted — **implemented (P1–P3, #174).** Tenant provisioning is now Crossplane `Tenant` claims...`
- **Findings:**
  - [SEVERITY: medium] Status/body describe the **`Tenant`/`XTenant`** model as the *current* live state, but that model was superseded by ADR-067 (Team→Product→Service; the kind is now **`XEnvironment`**). — **Evidence:** `infra/modules/crossplane/main.tf:222-231` (XEnvironment; no XTenant); ADR-046 contains 0 references to ADR-067. — **Proposed fix:** Add a status note "Tenant model superseded by ADR-067 (`XEnvironment`; Team→Product→Service)" mirroring ADR-049; update README index.
  - [SEVERITY: low] Decision bullet (line 89) states the Composition renders "the `DeveloperAccess-<team>` IAM role + EKS access entry." Per CLAUDE.md the v3 Composition emits only the in-cluster RoleBinding (#647). — **Evidence:** CLAUDE.md IAM Roles table; `infra/modules/crossplane/main.tf:16,402,604`. — **Proposed fix:** add the #647 caveat, or rely on the ADR-067 supersession note.
- **Decision concerns:** Foundational and largely sound; risk is staleness. The "Tenant control plane" framing is two model-generations old and should be cross-linked forward.

## ADR-047: EKS Pod Identity as the Standard for Pod AWS Identity
- **Status quoted:** `Accepted — supersedes ADR-018's rejection... Go-forward standard; the existing IRSA platform add-ons migrate during the planned stack rebuild, not in place.`
- **Findings:**
  - [SEVERITY: high] The central claim — IRSA add-ons "migrate **during the planned stack rebuild, not in place**" — is now **false**. The migration was completed **in place** under #594. argocd, cert-manager, external-dns, external-secrets, and the Kyverno-ECR role all now use `aws_eks_pod_identity_association`. — **Evidence:** `infra/modules/cert-manager/main.tf:107`, `external-dns/main.tf:90`, `external-secrets/main.tf:121`, `argocd/main.tf:140`, `policy/main.tf:236`; git log `3a4ca1b3 "finish IRSA → Pod Identity migration (ADR-047, #594)"`. — **Proposed fix:** Rewrite the status to "largely delivered in place (#594, 2026-06-24); EBS CSI remains on IRSA."
  - [SEVERITY: high] The claim (lines 44-48) that EBS CSI "keep[s] working on IRSA until the planned rebuild" mis-states the reason. It was deliberately kept on IRSA because managed-addon Pod Identity is unsupported — a permanent constraint, not rebuild-deferral. — **Evidence:** git log `44609a97 "revert(eks-addons): keep EBS CSI on IRSA — managed-addon Pod Identity unsupported here"`. — **Proposed fix:** Change the EBS CSI line to the managed-addon constraint.
  - [SEVERITY: low] Stale in-module comments still call the Kyverno-ECR role "IRSA" — cosmetic, out of ADR scope. — **Evidence:** `infra/modules/policy/main.tf:19,54` vs `:236`.
- **Decision concerns:** Decision was correct and executed faster/more completely than the ADR predicted; the ADR now under-claims and mis-explains live state — highest-value correction in the batch.

## ADR-048: Federated, Per-Cluster Crossplane for Tenant Provisioning
- **Status quoted:** `Accepted — **implemented (#174); migration complete.** ... both teams (alpha, bravo) are provisioned by `Tenant` claims...`
- **Findings:**
  - [SEVERITY: medium] Same Tenant/XTenant staleness as ADR-046: status describes alpha/bravo provisioned by **`Tenant` claims**, but live model is `XEnvironment` (ADR-067). Topology decision (per-cluster federated Crossplane) still valid; vocabulary/kind stale. — **Evidence:** `infra/modules/crossplane/main.tf:222-231`; 0 references to ADR-067. — **Proposed fix:** Add an ADR-067 supersession-of-vocabulary note.
  - [SEVERITY: low] The 2026-06-25 XAgent note correctly cross-references ADR-082. — **Evidence:** `docs/adrs/082-...md` present.
- **Decision concerns:** Decision quality good; only the tenant-noun is dated.

## ADR-049: Multi-Tenancy Model — Team, Tenant, and Zone
- **Status quoted:** `Accepted — **partially built, cutover pending (updated 2026-06-09).** **Partly superseded by ADR-067 (2026-06-11):**...`
- **Findings:**
  - [SEVERITY: low] **Best-maintained ADR in the batch**: explicitly carries the ADR-067 supersession, matches the README annotation, referenced docs exist. — **Evidence:** README row "Accepted (Zone/Customer partly superseded by ADR-067)". — **Proposed fix:** none.
  - [SEVERITY: low] Heavy present-tense `Tenant`/`teams.hcl`/`tenant-claims` in the body is contextually fine (status header declares it superseded), but those artifacts no longer exist. — **Proposed fix:** optional — tighten "today" to "the interim model (since retired)."
- **Decision concerns:** none of substance. The separation-of-axes insight is retained by ADR-067.

## ADR-050: Shared `build-sign` Reusable Workflow + Shared-Signer Policy Model
- **Status quoted:** `Accepted — extends ADR-042... **Live on preprod (2026-06-03): app-alpha and app-bravo migrated to thin callers...**`
- **Findings:**
  - [SEVERITY: medium] The "Not yet (future)" section + Decision point 4 name policy-module variables that **no longer exist**: `shared_signer_caller_repos`, `shared_signer_teams`, `verify_subjects`. The module moved to the per-**product** model (`verify_subjects_product`, derived from the `Product` registry). — **Evidence:** `grep` for those vars → NONE; live var `verify_subjects_product` at `infra/modules/policy/variables.tf:265-266`; the description of `trusted_ci_build_subject_regexp` (line 247) still references removed `shared_signer_caller_repos`. — **Proposed fix:** Update to registry-derived per-product policies (ADR-067/069); forward-point to ADR-069.
  - [SEVERITY: low] `trusted_ci_build_subject_regexp` exists and matches Decision point 4. — **Evidence:** `policy/variables.tf:246-247`.
  - [SEVERITY: low] The 2026-06-16 update (app-bravo/app-alpha retirement → New Product scaffolder) is consistent with current state.
- **Decision concerns:** Sound; only the policy-variable inventory drifted with the teams.hcl→registry migration.

## ADR-051: Backstage as the Developer Portal
- **Status quoted:** `Accepted — ... **authenticates via the centralized Dex broker (ADR-052)**, and renders the tenant model defined by ADR-049. Phases 2.0–2.3a are live...`
- **Findings:**
  - [SEVERITY: high] The status asserts Backstage "authenticates via the centralized Dex broker (ADR-052)" — now **false**: Backstage uses **direct Keycloak OIDC**; Dex + oauth2-proxy retired (ADR-052 itself marked superseded/REMOVED, cutover in ADR-053). ADR-051 carries **no amendment**. — **Evidence:** `infra/modules/backstage/variables.tf:125-134` (direct-Keycloak `oidc`; secret `platform/keycloak/backstage-oidc`); `docs/adrs/052-...:5-8`; CLAUDE.md "auth=DIRECT Keycloak OIDC." — **Proposed fix:** Add amendment: "Auth migrated from Dex to direct Keycloak OIDC (ADR-053); Dex/oauth2-proxy sections historical."
  - [SEVERITY: medium] Body repeatedly calls the catalog source **`XTenant` claims**; current kind is `XEnvironment` (ADR-067 Team→Product→Environment). — **Evidence:** `crossplane/main.tf:222-231`. — **Proposed fix:** note the `XTenant`→`XEnvironment` supersession.
  - [SEVERITY: low] "We track upstream Backstage (currently 1.51)" unverifiable from this repo (app in `asanexample/backstage`) and likely stale. — **Proposed fix:** drop the minor version / mark "as of writing"; **NEEDS LIVE/OWNER VERIFICATION**.
  - [SEVERITY: low] Endpoint `https://backstage.aws.refplat.org` + Terragrunt-not-GitOps deploy verify out.
- **Decision concerns:** Build-vs-buy + projection-from-git decisions sound and live, but the auth narrative is a generation stale and never amended — a reader would build the wrong (Dex) integration.

## ADR-052: Centralized Dex SSO Broker
- **Status quoted:** `Accepted, then **superseded by ADR-053 / ADR-059 and REMOVED** — Keycloak is the app-facing IdP of record; Dex (and the oauth2-proxy that fronted Backstage) were retired...`
- **Findings:**
  - [SEVERITY: low] Status accurate: no `dex` module exists; keycloak/keycloak-config modules do; README row matches; pointer to `docs/architecture/identity-and-sso.md` resolves. — **Evidence:** `ls infra/modules/dex` → none.
- **Decision concerns:** Exemplary lifecycle hygiene. No concerns.

## ADR-053: Identity & Cross-System Authorization Strategy
- **Status quoted:** `Accepted — **largely delivered (updated 2026-06-09).** ... **Dex + oauth2-proxy retired**; Backstage group-based RBAC shipped (#197).`
- **Findings:**
  - [SEVERITY: low] Headline status verifies: Keycloak modules live; Backstage on direct Keycloak OIDC; RBAC #197 shipped. — **Evidence:** `infra/modules/keycloak[-config]`; `backstage/variables.tf:125-134`.
  - [SEVERITY: medium] The 2026-06-08 amendment's "Unchanged" bullet (line 37) cites "access-as-code from **`_teams.hcl`**" as live. `_teams.hcl` no longer exists — model now derives from the git-native registries (Team CR + Product registry, ADR-063/067). Same stale source in Decision 3 (line 116). — **Evidence:** no `_teams.hcl`; CLAUDE.md "teams.hcl is retired"; ADR-063. — **Proposed fix:** Replace `_teams.hcl` with the git-native Team CR + Product registry (ADR-063/067).
  - [SEVERITY: low] Forward cross-refs (ADR-059, 063, 067, 068) all resolve.
- **Decision concerns:** Strong, well-amended; only the residual `_teams.hcl` source reference lags the migration.

## ADR-054: Platform Resilience & Business Continuity
- **Status quoted:** `Proposed — **strategy/direction.**`
- **Findings:**
  - [SEVERITY: low] Status (Proposed) matches the README index and the forward-looking tense; no overclaims. CNPG/Velero/AWS Backup named as *future* — consistent with the second-pass audit's "CNPG/Keycloak no-backup" open gap. — **Evidence:** README row "Proposed"; memory `project_tech_debt_second_pass`.
- **Decision concerns:** Appropriately scoped direction-setting.

## ADR-055: Compliance Assurance & Continuous Control Evidence
- **Status quoted:** `Proposed — **strategy/direction.**`
- **Findings:**
  - [SEVERITY: low] Status matches README; referenced artifacts exist incl. `docs/compliance/scp-control-mapping.md`; no overclaims. — **Evidence:** README row "Proposed"; file present.
- **Decision concerns:** Cleanly scoped direction ADR.

---

## Cross-cutting note

1. **Tenant→Environment / `XTenant`→`XEnvironment` (ADR-067) drift.** ADRs 046, 048, 050, 051 still describe the live model in the retired `Tenant`/`XTenant`/`teams.hcl`/`tenant-claims` vocabulary. Only ADR-049/052 carry the supersession note. Recommend a one-line ADR-067 supersession note on 046/048/050/051.
2. **"Deferred to the rebuild" claims that already happened in place.** ADR-047 (HIGH): says IRSA add-ons migrate at the rebuild, but #594 migrated them in place; EBS CSI is permanently on IRSA for a technical reason. ADR-051's Dex-auth status is the parallel identity-domain case (superseded in place by Keycloak OIDC, never amended). Both are ADRs whose execution outran the document.
