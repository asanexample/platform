# v3 Cutover — activating the ADR-067 platform (and what it surfaced)

How the additive, inert v3 stack (F1 → #389) becomes the **end state** (v3 live, v2 gone). The cutover is a
**coordinated change merged immediately before the from-scratch rebuild**; the rebuild then deploys the v3 state.
This doc is (1) the ordered cutover procedure, (2) an **end-to-end coherence trace** that walks one New-Product
flow through the whole v3 stack — which **surfaced real integration gaps** (the point of drafting this now), and
(3) the rebuild-runbook deltas.

> **Cutover model.** Everything built so far is additive + gated/inert (v2 byte-identical throughout). The cutover
> = (a) flip the gates on, (b) migrate the gitops data, (c) swap the CI gates, (d) remove v2 — as **one reviewed
> change**, merged just before the rebuild. The rebuild (a supervised destroy + from-scratch build) deploys it.
> Greenfield is the friend here: a from-scratch rebuild has **no stored v1alpha2 objects to convert**, so the
> v2→v3 schema/storage flip is clean.

## Preconditions (must be merged before the cutover)

| Piece | Status | Cutover-blocking? |
| ----- | ------ | ----------------- |
| F1 — v3 API (XEnvironment/Product/AccessGrant + gitops) | ✅ merged | yes |
| L2a — v3 Composition | ✅ merged | yes |
| L2b — ApplicationSet + verify-images-product + per-Product OIDC | ✅ merged | yes |
| #387 — restrict-environment-envelope | ✅ merged | yes |
| #389 — registry-sync apps | ✅ merged | yes |
| **#388 — product-gate + environment-gate (CI)** | ⛔ TODO | **yes** — without them the new gitops paths have no shift-left gate; the v2 teams-gate/tenant-claims-gate reject v3 |
| **L2c — projection rewrite (System/Component/Environment)** | ⛔ TODO | **yes (portal)** — else Backstage shows stale v2 tenant Systems |
| **L3b — golden-path-starters + app-repo restructure** | ⛔ TODO | **yes** — the ApplicationSet syncs `k8s/overlays/<stage>`; existing apps are flat `k8s/preprod/` (see Gap 2) |
| L3a — New Product scaffolder | ◻ for self-service | no (apps can be hand-migrated) |

## The cutover procedure (ordered)

1. **Migrate gitops data** (the substantive part):
   - `gitops/teams/*.yaml` → **v1alpha3** envelope (`allowedEnvironments`→`allowedStages`,
     `maxDedicatedZones`→`maxDedicatedIsolation {cluster,account}`, + `maxCrossTeamGrantsPerProduct`).
   - For each v2 app, write `gitops/products/<team>/<product>.yaml` (repo, tenancy, domains, defaultIsolation).
   - Convert each `gitops/tenant-claims/<env>/*.yaml` (XTenant) → `gitops/environments/<team>/<product>/<stage>.yaml`
     (XEnvironment): `name`→`product`, `environment`→`stage`, `apps.<app>`→`services.<svc>`.
   - Delete `gitops/tenant-claims/`.
2. **Flip the Team CRD storage to v1alpha3** (see **Gap 1**) — `storage: true` moves to v1alpha3; v1alpha2 stays
   served (or is dropped). Greenfield rebuild = no conversion needed.
3. **Flip the unit gates** (the activation):
   - `argocd-apps`: set `platform_repo_url` + `platform_repo_branch` → activates the per-Product ApplicationSet
     **and** the registry-sync apps. Remove the v2 `tenant_claims` sync (replaced by `environments`).
   - `github-oidc`: `v3_delivery_enabled = true` → per-Product OIDC roles; drop the per-team derivation.
   - `policy`: `enableEnvironmentEnvelope = true`, `enableImageVerification = true`, derive `verifySubjectsProduct`
     from `gitops/products`; (start `envelopeFailureAction: Audit`, flip to `Enforce` after a clean soak).
4. **Swap the CI gates:** `teams-gate` → v1alpha3 schema; `tenant-claims-gate` → **`environment-gate`** + add
   **`product-gate`** (#388).
5. **Remove v2** (in the same change): `xrd.yaml` (XTenant XRD), `composition-v2.yaml` (+ wrapper),
   `tenant-envelope.yaml`, `verify-images.yaml` (per-team), the v2 `verifySubjects`/`tenantRegistryMap`
   derivations, the per-team github-oidc roles.
6. **Roll the Backstage image** with the L2c projection (reads `gitops/products`+`environments`).
7. **Run the rebuild** (the supervised op) — it deploys the above from scratch.

## End-to-end coherence trace — and the gaps it surfaced

Walking one path — *New Product `alpha/shop` → first deploy* — through the v3 stack, checking every handoff:

```text
New Product PR ──(product-gate/environment-gate?)──► merge
   └► ArgoCD registry-sync (#389): Product CR (wave -2) + Team CR (-1) + XEnvironment claim (wave 0)
        └► admission: restrict-environment-envelope (#387) reads Team + Product CRs ──► admit
             └► Composition (L2a): namespace alpha-shop-dev, ECR team-alpha/shop-*, Pod-Identity, policies
                  └► app CI: build → ECR (per-Product OIDC role) → cosign-sign
                       └► ApplicationSet (L2b): sync <repo>/k8s/overlays/dev ──► verify-images-product admits ──► running
```

**The handoffs hold** — sync-wave ordering is correct (Product -2 / Team -1 land before Environment 0, so
`team-matches-product` + the envelope have their CRs); the Composition's `team`/`product` namespace labels are
exactly what `restrict-images`/`verify-images-product` select on; the ApplicationSet namespace goTemplate mirrors
the Composition's (incl. truncate-hash). **But the trace surfaced four real gaps:**

### 🔴 Gap 1 — Team CRD storage version vs the v3 apiCall

`restrict-environment-envelope` reads the Team via `apiCall: /apis/platform.refplat.org/**v1alpha3**/teams/<team>`
and uses `team.spec.envelope.**allowedStages**`. F1 added v1alpha3 as a **served, non-storage** version
(`conversion: None`). If a Team is *stored* as v1alpha2 (`allowedEnvironments`), a v1alpha3 GET with no conversion
returns the v2 shape → **`allowedStages` is null and the envelope check silently passes**. **Fix:** the cutover
must make **v1alpha3 the storage version** and the gitops Teams must be authored v1alpha3. Greenfield rebuild =
clean (nothing stored to convert), but this is an explicit, easy-to-miss cutover step. *(Same applies to the
Product/AccessGrant apiCalls — all must be the stored/served version the policies query.)*

### 🔴 Gap 2 — existing app repos are the wrong shape for the ApplicationSet

The per-Product ApplicationSet syncs **`<repo>/k8s/overlays/<stage>`** (ns/host-agnostic base + per-stage
overlays). The live apps (`app-alpha`, `app-bravo`) are **flat `k8s/preprod/` with a hardcoded namespace**. So
the ApplicationSet would find no `k8s/overlays/dev` and deploy nothing. **Fix:** restructure each app repo to the
v3 layout (this is L3b's `_platform` overlay shape) *before* it can be delivered by v3 — or recreate it via New
Product. **This is per-app migration work that must precede the cutover for any app we want live on v3.**

### 🟡 Gap 3 — the gates are hard-cutover-blocking, not optional

`teams-gate` hard-pins `apiVersion: v1alpha2` + `allowedEnvironments`; `tenant-claims-gate` parses XTenant
fields. The moment the cutover writes v1alpha3 Teams + `gitops/environments`, **both gates fail every PR** unless
swapped in the *same* change. So #388 (product-gate + environment-gate) + the teams-gate v3 bump are part of the
cutover commit, not a follow-up.

### 🟡 Gap 4 — the digest's first home on a fresh build

ADR-069 §4 (revised) leaves the digest in the app-repo overlay, promotion = P2. For the **first** deploy of a
migrated/new app, the overlay's `images:` must carry a real digest (the app's CI writes it). On a from-scratch
rebuild the app images must be **built + pushed first** (the per-Product OIDC role exists, but the rebuild order
must build images before/at ArgoCD sync, or the first sync deploys a not-yet-pushed image). Add to the rebuild
runbook's image-prep step.

## What the trace makes the next build targets

In priority order (all cutover-blocking except L3a):

1. **#388** — `product-gate` + `environment-gate` + teams-gate v3 (Gap 3).
2. **App-repo restructure / L3b starters** — the `k8s/overlays/<stage>` ns-agnostic layout (Gap 2).
3. **L2c** — the projection rewrite (portal correctness).
4. **The cutover commit itself** — flip storage to v1alpha3 (Gap 1), migrate gitops, flip gates, remove v2.
5. Rebuild-runbook deltas — image-prep ordering (Gap 4), the new gitops paths, the v3 unit inputs.

## Rebuild-runbook deltas (`platform-rebuild-from-scratch.md`)

- Build + push every app image to its product-scoped ECR (`team-<team>/<product>-<service>`) **before** ArgoCD
  syncs the per-Product ApplicationSets (Gap 4).
- The crossplane unit now deploys the v3-only tenant chart (XEnvironment XRD + Composition; XTenant removed).
- The argocd-apps unit needs `platform_repo_url`/`platform_repo_branch`; it syncs `gitops/products` +
  `gitops/environments` (not `gitops/tenant-claims`).
- Teams/Products/Environments project in sync-wave order (-1 / -2 / 0).
- Start `envelopeFailureAction: Audit`; flip to `Enforce` after one clean reconcile (matches the v2 A6 pattern).
