# Delivery Plan — Tenant API v2 + Identity Strategy (the rebuild cutover)

Sequenced delivery for the target tenant model ([ADR-049](../adrs/049-tenant-model-team-tenant-zone.md),
[schema](../architecture/tenant-api-v2.md)) and the identity/authz strategy
([ADR-053](../adrs/053-identity-and-cross-system-authorization-strategy.md)), plus the enterprise-readiness
ADRs ([054](../adrs/054-platform-resilience-and-business-continuity.md)–[057](../adrs/057-service-identity-and-east-west-zero-trust.md))
that surround them. This is the *how and in what order*; the ADRs are the *what and why*.

## The core constraint

The breaking v2 changes (namespace `team-<team>` → `<team>-<tenant>`, the v2 XRD storage version, the v2
Composition, placement, Zones, the Dex→Keycloak swap) **land with the planned rebuild, not in place** (ADR-049
plus the planned-rebuild decision). But **a rebuild applies whatever IaC exists at apply time** — so the v2 work
must be *written and apply-ready before* the teardown. The teardown is the **last** step (the cutover), not the
first.

Every item below is tagged:

- 🟢 **start-now** — additive / offline-testable; build it against the current stack (or with no cluster at
  all) without breaking anything.
- 🔴 **rebuild-gated** — the breaking cutover; stages behind the rebuild topology.

The discipline: get every 🟢 to apply-ready and render-clean, *then* do the 🔴 cutover in one pass.

> **Data posture.** Losing data during the rebuild is **expected and fine** — it's a deliberate
> destroy-and-recreate. The rebuild is **not** treated as lossy and is **not** gated on backups. The single
> success criterion is **full reconstructability from code**: `platctl bootstrap` / `terragrunt run --all apply`
> rebuild the entire platform from scratch with **no manual steps and no hidden/orphaned state**. The rebuild
> *is* the reproducibility test. (ADR-054's backup/DR concerns *unplanned* production failure + regulated-tenant
> recovery on the running platform — still relevant, but **not a rebuild prerequisite**.)

## Validation strategy (how we test without breaking prod)

- **`crossplane render`** — render a Composition against an example claim **offline, no cluster**. The bulk of
  the Composition + XRD work iterates here; wire it into CI against the canonical + alpha/bravo example claims.
- **Schema CI** — apply the XRD to an ephemeral kind cluster (or `kubectl --dry-run=server`) and validate every
  example claim, including the reserved dimensions.
- **Sandbox smoke** — a real apply in the **Test sandbox account** (`docs/runbooks/test-sandbox-account.md`)
  before trusting the cutover, for the AWS-provider paths `render` can't exercise.
- **Plan-only** for the Terragrunt-side pieces (Keycloak module, Zones) per the testing convention.

## Two tracks, one keystone

```text
Track A — Model (Crossplane)              Track B — Identity (ADR-053)
  A1 v1alpha2 XRD ─────────┐
                           ▼
  A2 Team object ◀──── KEYSTONE ────▶ B2 access-model-as-code generators
       │                                   │
  A3 Composition v2                    B1 Keycloak module (parallel, independent)
  A4 Placement                         B3 ArgoCD OIDC cutover
  A5 Zones                             B4 Backstage RBAC (#197)
  A6 cutover mechanics                 B5 Dex→Keycloak migration
```

The **Team object (A2)** is the keystone: both the envelope-enforcement plane (Kyverno reads the projected
`Team` CR) and every ADR-053 generator read it. A1 makes it expressible; nothing downstream of A2 starts until
it lands. **B1 (Keycloak)** is the one big piece that parallelizes from day one — it's additive infra
independent of the model.

## Phases

### Phase 0 — Foundations (🟢 all start-now, parallelizable)

| ID | Deliverable | Tag | Depends on | Test |
| -- | ----------- | --- | ---------- | ---- |
| **A1** | `v1alpha2` XRD authored in the crossplane module, **served alongside** `v1alpha1` (not yet `referenceable`/storage) + an offline `crossplane render` / schema-validation CI harness over the canonical + translated alpha/bravo claims | 🟢 | — | render + kind dry-run |
| **B1** | Keycloak module + unit — brokering to Identity Center (SAML up), CNPG-backed, HA, Tailscale-internal; stood up **alongside** Dex (not yet the app IdP) | 🟢 | CNPG (live) | plan-only + manual login |

*(No pre-teardown backup slice — data loss in the rebuild is expected and fine; see the Data posture note above.
The rebuild's bar is reconstructability, not preservation.)*

### Phase 1 — The keystone (🟢)

| ID | Deliverable | Tag | Depends on | Test |
| -- | ----------- | --- | ---------- | ---- |
| **A2** | **Team object** — the `Team` XRD/CRD (projected-CR shape), the canonical Team record source, the registry→projected-CR sync, the envelope schema; + the **Kyverno envelope-admission policy** extending the S1 `restrict-tenant-control-plane` backstop, in **audit mode** | 🟢 | A1 | render + kind, policy in audit |
| **B2** | **Access-model-as-code** schema + generators (read the Team object): Keycloak groups/roles/clients/mappers (TF provider), Identity Center assignments, ArgoCD policy, k8s RoleBindings, Backstage policy. Built + **plan/render-tested**; wiring each generator live is staged | 🟢 | A2, B1 | TF plan + render |

### Phase 2 — Composition & identity wiring (🟢 build/render-test now; apply at cutover)

| ID | Deliverable | Tag | Depends on | Test |
| -- | ----------- | --- | ---------- | ---- |
| **A3** | **Composition v2** — renders the v2 footprint from a v2 claim: namespace `<team>-<tenant>`, **per-app identity** (a role+SA per app, not one `Pod-team`), the reserved-dimension stubs (`dataServices`/`encryption`/`lifecycle` inert). Fully offline-renderable | 🟢 | A1, A2 | `crossplane render` in CI |
| **B3** | **ArgoCD OIDC** against Keycloak — named group claims + **team-scoped Projects** (retire the UUID hack). Stageable against the standing Keycloak | 🟢→🔴 | B1, B2 | staged login |
| **B4** | **Backstage RBAC (#197)** on OIDC group claims — *can ship interim on Keycloak before the rebuild if B1 is up* | 🟢 | B1, B2 | manual RBAC check |

### Phase 3 — Rebuild-gated topology (🔴 needs the federated rebuilt clusters)

| ID | Deliverable | Tag | Depends on | Test |
| -- | ----------- | --- | ---------- | ---- |
| **A5** | **Zones** — platform-owned Terragrunt-provisioned **pooled** zones (the `tiers × locations` cross-product, ADR-048 = a Zone *is* an env+location cluster running its own Crossplane) + the cloud-neutral **vending interface** (impl deferred) | 🔴 | rebuild topology | sandbox apply |
| **A4** | **Placement** — the thin layer resolving a Tenant's `(tier, tenancy, residency)` intent to a concrete Zone/cluster and writing `status.placement`. Resolver logic designed in Phase 2, wired here | 🔴 | A3, A5 | sandbox |

### Phase 4 — The cutover (🔴 = the rebuild itself)

Pre-flight gate: every 🟢 renders/plans clean, passed a sandbox smoke apply, **and a full `platctl bootstrap`
rebuild in the sandbox proves the platform reconstructs from code with zero manual steps** (the rebuild's real
success criterion). Then, in one pass:

| ID | Deliverable | Tag |
| -- | ----------- | --- |
| **A6** | Flip XRD **storage/`referenceable` → `v1alpha2`**, bind Composition v2; retire `teams.hcl` + the interim delivery split (claims already GitOps via ArgoCD — schema changes, the pipe doesn't); confirm the ArgoCD SA stays in the S1 platform-principal exclusion; flip the envelope policy **audit → enforce** | 🔴 |
| **B5** | **Dex → Keycloak** as the app IdP; retire the per-app SAML certs/attribute-mapping toil | 🔴 |
| **X** | **Teardown old stack → rebuild with v2 IaC → apply v2 claims (alpha/bravo translated) → validate** | 🔴 |

### Phase 5 — Enterprise follow-ons (post-rebuild)

The remaining capability ADRs, sequenced after the model+identity land — none block the cutover:

- [ADR-054](../adrs/054-platform-resilience-and-business-continuity.md) — backup/DR, DR drills, multi-region triggers for the **running** platform (unplanned failure + regulated-tenant recovery). *Not* a rebuild prerequisite — the intentional rebuild is expected to lose data.
- [ADR-055](../adrs/055-compliance-assurance-and-continuous-control-evidence.md) — compliance assurance / continuous evidence.
- [ADR-056](../adrs/056-progressive-delivery-and-safe-rollback.md) — Argo Rollouts progressive delivery.
- [ADR-057](../adrs/057-service-identity-and-east-west-zero-trust.md) — Cilium mTLS / SPIFFE east-west.

## Critical path & parallelism

```text
A1 ──▶ A2 ──┬──▶ A3 ──────────────▶ A4 ──┐
            └──▶ B2 ──▶ B3/B4           │
B1 ─────────────┘ (parallel from day 0) │
A5 ─────────────────────────────────────┴──▶ Phase 4 cutover ──▶ Phase 5
```

- **Longest chain:** A1 → A2 → A3 → A4 → cutover. Start A1 immediately; it gates everything.
- **Run in parallel now:** B1 (Keycloak) has no model dependency.
- **Most value-per-effort first PR:** **A1** — it makes the schema executable and gives A2/A3/B2 something to
  compile against; non-destructive; de-risks the whole rebuild.

## Open questions / deferred decisions

- **Dedicated-zone vending mechanism** — cloud-neutral interface now, implementation deferred (ADR-049).
- **Aggregate-quota controller** — report-first; hard-enforce only if a team pushes the cap (ADR-049).
- **Interim Backstage RBAC (B4)** — ship on Keycloak *before* the rebuild, or wait for the full cutover?
- **Keycloak go-live** — run alongside Dex through Phases 1–3, or hold the IdP swap entirely to Phase 4?
- **Reserved dimensions** (`dataServices`, BYOK, lifecycle) — stubbed inert in A3; realized in Phase 5+ on
  their own paved-road timelines.

## Where we are (updated 2026-06-09 — most tracks are done; this is now the last mile + cutover)

- ✅ **Track A built + render-tested (CI):** **A1** v1alpha2 XRD (served, not yet storage), **A2** Team CRD +
  projection + **envelope Kyverno policy (audit mode)**, **A3** Composition v2 (namespace `<team>-<name>`,
  per-app Pod-Identity, per-app ECR). Offline-renderable via `.tenant-api-tests/{run,render}.sh`.
- ✅ **Track B largely LIVE:** **B1** Keycloak, **B3** ArgoCD OIDC, **B4** Backstage RBAC (#197), **B5**
  Dex→Keycloak (Dex + oauth2-proxy retired) — all landed live. B2 (access-model-as-code generators) partial
  (keycloak-config generates groups/roles).
- 🟡 **In progress / not done (the remaining work):**
  - ✅ **Git-native Team** ([ADR-063](../adrs/063-team-as-first-class-git-object.md)) — `Team` CRs authored as
    YAML in `gitops/teams/{alpha,bravo}.yaml`, ArgoCD-synced via a new `teams` app (`argocd-apps` module,
    `sync-wave: "-1"` ahead of tenant-claims); the `crossplane` unit now passes `teams = {}` (CRD stays, Helm
    projection off) and the `keycloak-config`/`argocd` consumers read the git YAMLs (`fileset`+`yamldecode`).
    `_teams.hcl` retired. Plan-verified: crossplane = the single intended Helm-values diff, argocd = no-op,
    argocd-apps = the new `teams` project+app.
  - 🟡 the **delivery-consumer migration** (policy/github-oidc/argocd-apps → v1alpha2 claims), the v2 **claim
    translation**, and **A6 cutover** (storage flip → v1alpha2, bind Composition v2, envelope audit→enforce)
    + the rebuild.
- 🔵 **Deferred for the dev env:** **A4 placement** + **A5 Zones/Customer/vending** — degenerate on a single
  workload cluster (every claim lands on preprod); build when a second zone exists.
- 📋 Execution plan for the remaining work: BACK Phase 3 self-service ([ADR-062](../adrs/062-self-service-tenant-provisioning.md))
  is built **on top of** this cutover, after the rebuild.
