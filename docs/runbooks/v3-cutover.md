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
| 5a | remove v2 supply-chain — per-team `verify-images.yaml` + `verify-attestations.yaml` (superseded by the product versions; render nothing now) | ✅ done — helm green |
| 5b | remove v2 — XTenant `xrd.yaml` + `composition-v2.yaml`(+file), v1alpha2 Team version block (Team CRD now v1alpha3-only, storage), per-team `image-registries.yaml` per-team block (cluster floor kept) + `httproute-hostnames.yaml`, github-oidc per-team roles + claims locals, dead policy-unit locals, **the `.tenant-api-tests` harness → v3-only** (run.sh + render.sh, v2 fixtures deleted) | ✅ done — run.sh + render.sh green |
| 5c | **fix `tenant-control-plane.yaml` → `v1alpha3/XEnvironment`** (was guarding the removed `v1alpha1/XTenant` → the v3 composite was unguarded; defense-in-depth, low exposure since the XRD is cluster-scoped) + the `.kyverno-tests` render assertion | ✅ done — kyverno-tests green |
| 5e | removed `tenant-envelope.yaml` + added the v3 **environment-envelope kyverno behavioral test** (6 groups, Team+Product apiCall-mocked, all 8 rules). **Found + fixed 2 MORE admission gaps the bash shift-left masked:** (a) `customer-iff` used nested `all`-in-`any` `deny.conditions` → kyverno 1.18 **errors** (policy skipped) → split into two flat rules (`customer-required-per-customer-prod` + `customer-forbidden-on-pooled`); (b) `kyverno-read-platform-teams` granted only `teams` → the Product apiCall 403s → team-matches-product/customer rules **silently skip** → added `products`. tenant-policies chart 0.5.0 | ✅ done — full .kyverno-tests harness green |
| 5d | removed the 7 dead policy module vars + plumbing; removed the crossplane `charts/teams` Helm projection (charts/teams + helm_release + var.teams + unit `teams={}`; depends_on re-pointed to crossplane_tenant); orphaned registry-values.yaml + v3 README | ✅ done — tofu validate clean both modules |
| 5 | crossplane `tenant` (0.3.0) + policy `policies-chart` (0.2.0) Chart.yaml bumps | ✅ done |
| 6a | #285 Tenant Status card re-pointed to the v3 Environment (backstage#36, backward-compatible: cr-* annotations w/ v2 xtenant fallback, kind-agnostic filter+links) — merged + image rolled | ✅ done |
| 6b | L2c frontend part 2 (backstage#37): a catalog relation processor (ownedBy/partOf for kind:Environment) + the team-tenants card → Environments. kind:Environment uses the default entity page (cards attach by annotation filter, no dedicated EntityPage needed). Merged, image 4fbd38d3 | ✅ done |
| 6c | the `platformProjection.mode: 'v3'` **activation flip** — all L2c frontend code is pre-positioned + deployed; the cutover sets `mode: 'v3'` in the backstage app-config (no new image needed) | ⛔ TODO (cutover step) |
| 7 | app-repo `deploy.yml` rewire (build `team-<team>/demo-web`; pin the digest into `overlays/dev` via yq) + `preview.yml`/`validate.yml` v3 + delete `k8s/preprod/` — **PRs prepared** (app-bravo#10, app-alpha#35), MERGE-AT-CUTOVER (the product-scoped ECR doesn't exist until the rebuild, so the build checks are expected-red until then — mirrors the v2-rebuild A9 PRs) | ✅ prepared |
| 8 | rebuild-runbook deltas — the "Rebuild-runbook deltas" section below is now a full ordered teardown→merge→bootstrap→Gap-4-image-prep→soak procedure; `platform-rebuild-from-scratch.md` updated (XTenant→XEnvironment refs fixed + a v3-cutover pointer) | ✅ done |

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

**First-deploy OutOfSync is EXPECTED and self-converges (no manual step needed).** A brand-new Environment's
overlay ships `:placeholder` until the app's first CI build commits the signed-digest pin — a *separate* commit
after the build-trigger push. Between those two commits ArgoCD syncs the pre-pin revision, Kyverno
`verify-images-product` rejects the unpinned image, and the App shows `OutOfSync`/`SyncFailed`. This is normal:
the per-Product ApplicationSet now uses a **fail-fast retry** (`local.first_deploy_retry`, limit 4 / 15s→2m,
vs the platform apps' 45-min `sync_retry`), so the doomed pre-pin sync gives up in ~minutes and `selfHeal`
picks up the pin commit (a revision change) automatically — converging within ~one cycle of the pin landing.
You should NOT need `argocd app terminate-op` anymore; if you want to shortcut the wait, it still works
(`argocd app terminate-op <app> && argocd app get <app> --hard-refresh`). The proper end-state fix (build+pin in
one revision) is the P2 promote-by-PR redesign (#377).

## What the trace makes the next build targets

In priority order (all cutover-blocking except L3a):

1. ~~**#388** — `product-gate` + `environment-gate`~~ ✅ merged (#400). teams-gate v3 bump stays in the cutover commit (Gap 3).
2. ~~**App-repo restructure / L3b**~~ ✅ done for the live apps — `app-alpha`, `app-bravo` on `k8s/base` + `overlays/<stage>` (Gap 2).
3. ~~**L2c projection**~~ ✅ data layer done (backstage#35, mode-gated; inert image rolled #403). The frontend re-point (kind:Environment EntityPage + relation processor + #285/team-tenants cards) lands with the cutover's backstage roll (step 6).
4. **The cutover commit itself** — flip Team CRD storage to v1alpha3 (Gap 1), migrate gitops, flip gates + projection mode, remove v2. ◀ the remaining cutover-blocking work.
5. Rebuild-runbook deltas — image-prep ordering (Gap 4), the new gitops paths, the v3 unit inputs.

## Rebuild-runbook deltas (`platform-rebuild-from-scratch.md`)

The cutover commit deploys via a supervised teardown + from-scratch rebuild (greenfield = no stored v1alpha2 to
convert). The ordered procedure, with the v3 deltas:

1. **Teardown** the live v1 cluster (`platctl teardown`) — as today.
2. **Admin-merge the cutover commits** (teardown-before-merge, so there's no broken window):
   - platform `feat/v3-cutover` (installments 1–5e + 5d) — NOT via a normal PR (the base-branch v2 gates reject
     it); admin-merge.
   - the app cutover PRs (app-bravo#10, app-alpha#35) — their build checks were expected-red pre-cutover.
   - set `platformProjection.mode: 'v3'` in the Backstage app-config (6c — a one-line flip; image 4fbd38d3 already
     carries all the L2c frontend, so NO new backstage image).
3. **Bootstrap** (`platctl bootstrap`). v3 deltas the rebuild now deploys:
   - **crossplane** unit deploys the **v3-only** tenant chart (XEnvironment XRD + composition-v3 + the Team /
     Product / AccessGrant CRDs; XTenant XRD + composition-v2 removed). Team CRD storage = **v1alpha3** (Gap 1).
     `tenant_policy_values.enableEnvironmentEnvelope: true`, `envelopeFailureAction: Audit` (the v3 envelope's
     first soak). `crossplane-tenant-policies` installs after `crossplane_tenant` (the `crossplane-teams` Helm
     projection is gone — Teams are git-native).
   - **argocd-apps** unit needs `platform_repo_url`/`platform_repo_branch`; it syncs `gitops/products` +
     `gitops/environments` (registry-sync) + the per-Product ApplicationSets — NOT `gitops/tenant-claims`.
     `enable_teams` still syncs `gitops/teams`. Sync-wave order: Team -1 / Product -2 / Environment 0.
   - **github-oidc** `v3_delivery_enabled: true` (per-Product ECR-push roles). **policy** (preprod):
     `verify_subjects_product` from `gitops/products`; the v2 per-team supply-chain inputs are gone.
4. **Gap-4 app image pre-build (the easy-to-miss ordering step).** Each Environment's `services.<svc>` ships
   with NO image (first-deploy state) and the overlay pins `:placeholder` → the per-Product ApplicationSet would
   sync a non-existent tag (ImagePullBackOff). After step 3 has created the product-scoped ECR
   (`team-<team>/demo-web`, by the XEnvironment reconcile), **trigger each app's CI** (re-run the `deploy.yml`
   workflow on `main`, or push a trivial commit) so it builds → signs → pins the real digest into
   `k8s/overlays/dev`. Only THEN does the ApplicationSet sync a pullable, signed, verify-images-product-passing
   image. (Merging app#10/#35 in step 2 is itself a push that triggers `deploy.yml` — confirm the ECR exists
   first, else that run fails and must be re-run.)
5. **Validate + soak**, then flip the v3 envelope `envelopeFailureAction: Audit → Enforce` after one clean
   reconcile (matches the v2 A6 pattern). `platctl validate` covers the v3 footprint.

**charlie** (the v2 throwaway tenant) is not migrated — re-provision it via the v3 self-service flow if needed.
