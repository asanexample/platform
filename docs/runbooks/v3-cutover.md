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
| #388 — product-gate + environment-gate (CI) | ✅ merged (#400) | yes |
| L2c — projection rewrite (System/Component/Environment) | ✅ data layer done (backstage#35, mode-gated; image rolled inert via #403). Frontend re-point = cutover follow-up | yes (portal) |
| L3b — app-repo restructure (`k8s/base` + `overlays/<stage>`) | ✅ done for the live apps (app-alpha, app-bravo) | yes — see Gap 2 |
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
4. **Swap the CI gates:** `teams-gate` → v1alpha3 schema; retire `tenant-claims-gate` (the `v3 gitops Gate` —
   `product-gate` + `environment-gate`, #388 — is already live and required).
5. **Remove v2** (in the same change): `xrd.yaml` (XTenant XRD), `composition-v2.yaml` (+ wrapper),
   `tenant-envelope.yaml`, `verify-images.yaml` (per-team), the v2 `verifySubjects`/`tenantRegistryMap`
   derivations, the per-team github-oidc roles.
6. **Flip the Backstage projection to v3** — set `platformProjection.mode: 'v3'` (the L2c image is already
   rolled, inert, via #403; no new image needed). Land the L2c frontend follow-ups in the SAME backstage roll:
   the `kind:Environment` EntityPage + a catalog relation processor (ownedBy/partOf for the custom kind) +
   re-point the #285 status card to the `cr-*` annotations + the team-tenants card → Environments.
7. **Run the rebuild** (the supervised op) — it deploys the above from scratch.

## Cutover commit — build status (`feat/v3-cutover` branch)

The cutover commit is accumulated on the **`feat/v3-cutover`** branch — NOT mergeable via a normal gated PR (the
base-branch v2 `teams-gate`/`tenant-claims-gate` would reject the v1alpha3 teams + claim deletions, Gap 3), so it
is **admin-merged during the rebuild** (teardown-before-merge). Validated **offline** by the v3 gate scripts +
`crossplane render` + the projection logic.

| Step | Piece | Status |
| ---- | ----- | ------ |
| 1 | gitops/teams → v1alpha3 (`allowedStages`, `maxDedicatedIsolation`) | ✅ done (4 teams) |
| 1 | gitops/products + environments (alpha, bravo) ; **charlie dropped** (throwaway — re-provision via v3 self-service); tenant-claims/ deleted | ✅ done — gate + render green |
| 2 | Team CRD storage → v1alpha3 (Gap 1; v1alpha2 served:false) | ✅ done |
| 3 | unit flips — github-oidc `v3_delivery_enabled=true`; argocd-apps retire `enable_tenant_claims` + set `platform_repo_url`; preprod crossplane `enableEnvironmentEnvelope=true` (envelope Audit-first soak) | ✅ done |
| 3 | preprod policy v3 migration — `verify_subjects_product` derived from gitops/products; **NEW `verify-attestations-product.yaml`** (the missing SLSA-provenance analog — L2b had only `verify-images-product`, unwired); v2 per-team `verify_subjects`/`tenant_registry_map`/`tenant_hostname_patterns`/`attest_caller_repos` emptied. **helm-template green: 2 verify-images-product + 2 verify-attestations-product, 0 v2 per-team** | ✅ done |
| 4 | `teams-gate` → v1alpha3 (`allowedStages`, `maxDedicatedIsolation.{cluster,account}`, env-deletion guard reads gitops/environments) + workflow env ; **retired `tenant-claims-gate.yml` + `.github/scripts/tenant-gate/`** (the `v3 gitops Gate` #388 replaces it) | ✅ done — gate green on migrated teams, rejects v1alpha2 |
| 5 | remove v2 — XTenant `xrd.yaml`, `composition-v2.yaml`(+wrapper), `tenant-envelope.yaml`, per-team `verify-images.yaml`/`verify-attestations.yaml`, per-team github-oidc roles, the v1alpha2 Team version block + the now-unused policy-unit v2 locals | ⛔ TODO |
| 5 | crossplane `tenant` (0.3.0) + policy `policies-chart` (0.2.0) Chart.yaml bumps | ✅ done |
| 6 | Backstage `platformProjection.mode: 'v3'` + the L2c frontend follow-ups (kind:Environment EntityPage + relation processor + #285/team-tenants re-point) | ⛔ TODO |
| — | app-repo `deploy.yml` rewire (push product-scoped image + pin digest into `overlays/<stage>`) + delete `k8s/preprod/` (Gap 4) | ⛔ TODO (per app repo) |
| 7 | rebuild-runbook deltas (image-prep ordering, new gitops paths, v3 unit inputs) | ⛔ TODO |

**Naming locked by the migration:** Product = the v2 tenant `name` (`demo`); Service = `web` (single service;
image `team-<team>/demo-web`, matching the F1 example + the Gap-2 app restructure); the named SA stays the app's
`app-<team>` (the app deployment's `serviceAccountName`). v2 `developerAccess` drops — subsumed by the ADR-068
access model (no per-Environment field).

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

### ✅ Gap 2 — existing app repos are the wrong shape for the ApplicationSet — RESOLVED

The per-Product ApplicationSet syncs **`<repo>/k8s/overlays/<stage>`** (ns/host-agnostic base + per-stage
overlays); the live apps were **flat `k8s/preprod/` with a hardcoded namespace**. **Done (#376):** both
`app-alpha` ([#34](https://github.com/asanexample/app-alpha/pull/34)) and `app-bravo`
([#9](https://github.com/asanexample/app-bravo/pull/9)) now carry `k8s/base/` (ns-/host-agnostic, image
product-scoped `team-<team>/demo-web`) + `k8s/overlays/{dev,test,uat,staging,prod}/`, **additively** —
`k8s/preprod/` is kept byte-identical so v2 delivery is untouched, and a CI job asserts every overlay builds
ns-agnostic. **Remaining at cutover:** rewire each app's `deploy.yml` to push the product-scoped image and pin
the digest into `overlays/<stage>` (the first-deploy image-prep, Gap 4), then remove `k8s/preprod/`.

### 🟡 Gap 3 — the gates are hard-cutover-blocking, not optional — PARTIALLY ADDRESSED

`teams-gate` hard-pins `apiVersion: v1alpha2` + `allowedEnvironments`; `tenant-claims-gate` parses XTenant
fields. The moment the cutover writes v1alpha3 Teams + `gitops/environments`, **both gates fail every PR** unless
swapped in the *same* change. **Done (#388 / #400):** the `product-gate` + `environment-gate` (the new
`v3 gitops Gate`) are merged and inert (classify-first; the v3 surfaces are empty until cutover). **Still in the
cutover commit:** the `teams-gate` v1alpha3 bump + retiring `tenant-claims-gate` in favour of the
`environment-gate` — those must land in the *same* change that migrates the gitops data.

### 🟡 Gap 4 — the digest's first home on a fresh build

ADR-069 §4 (revised) leaves the digest in the app-repo overlay, promotion = P2. For the **first** deploy of a
migrated/new app, the overlay's `images:` must carry a real digest (the app's CI writes it). On a from-scratch
rebuild the app images must be **built + pushed first** (the per-Product OIDC role exists, but the rebuild order
must build images before/at ArgoCD sync, or the first sync deploys a not-yet-pushed image). Add to the rebuild
runbook's image-prep step.

## What the trace makes the next build targets

In priority order (all cutover-blocking except L3a):

1. ~~**#388** — `product-gate` + `environment-gate`~~ ✅ merged (#400). teams-gate v3 bump stays in the cutover commit (Gap 3).
2. ~~**App-repo restructure / L3b**~~ ✅ done for the live apps — `app-alpha`, `app-bravo` on `k8s/base` + `overlays/<stage>` (Gap 2).
3. ~~**L2c projection**~~ ✅ data layer done (backstage#35, mode-gated; inert image rolled #403). The frontend re-point (kind:Environment EntityPage + relation processor + #285/team-tenants cards) lands with the cutover's backstage roll (step 6).
4. **The cutover commit itself** — flip Team CRD storage to v1alpha3 (Gap 1), migrate gitops, flip gates + projection mode, remove v2. ◀ the remaining cutover-blocking work.
5. Rebuild-runbook deltas — image-prep ordering (Gap 4), the new gitops paths, the v3 unit inputs.

## Rebuild-runbook deltas (`platform-rebuild-from-scratch.md`)

- Build + push every app image to its product-scoped ECR (`team-<team>/<product>-<service>`) **before** ArgoCD
  syncs the per-Product ApplicationSets (Gap 4).
- The crossplane unit now deploys the v3-only tenant chart (XEnvironment XRD + Composition; XTenant removed).
- The argocd-apps unit needs `platform_repo_url`/`platform_repo_branch`; it syncs `gitops/products` +
  `gitops/environments` (not `gitops/tenant-claims`).
- Teams/Products/Environments project in sync-wave order (-1 / -2 / 0).
- Start `envelopeFailureAction: Audit`; flip to `Enforce` after one clean reconcile (matches the v2 A6 pattern).
