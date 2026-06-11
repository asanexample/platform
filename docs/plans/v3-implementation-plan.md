# v3 Implementation Plan — building the ADR-067 domain model

The sequenced build plan for the ADR-067/068/069 design (the v1alpha3 model: Team / Product / Service /
Environment / Customer). The normative contract is [platform-domain-api.md](../architecture/platform-domain-api.md);
this is *how we get there from the live v2*.

## Cutover model

The live stack runs **v2** (`XTenant`, `gitops/tenant-claims/`, Composition v2, per-`(team,app)` ArgoCD
Applications, the per-tenant projection). v3 is a **breaking** change (renamed CRs, new gitops layout, rewritten
delivery + catalog). Per ADR-067, it **rides the planned rebuild** — not an in-place migration.

So the model is the one the v2 A/B-tracks already used: **build v3 additively on branches, CI-render-tested,
deploy nothing live; the rebuild is the cutover.** Backstage-side and starter-repo work can roll independently
of the platform rebuild, but only *show* v3 once the platform side is rebuilt.

**No v1→v2-style migration burden:** v1alpha1 was dropped cleanly at the A6 cutover, so v2→v3 is a greenfield
rename, not a dual-version migration.

## Naming locked (from the schema)

| Thing | v2 | **v3** |
|---|---|---|
| Claim CR | `XTenant` v1alpha2 | **`XEnvironment` v1alpha3** |
| Namespace | `<team>-<name>-<env>` | **`<team>-<product>-<stage>[-<customer>]`** |
| ECR repo | `team-<team>/<app>` | **`team-<team>/<product>-<service>`** |
| Pod IAM role | `Pod-<team>-<name>-<env>-<app>` | **`Pod-<team>-<product>-<stage>-<service>`** |
| Image-scope policy | `team-<team>/*` | **`team-<team>/<product>-*`** |
| gitops | `tenant-claims/<env>/` | **`products/<team>/` + `environments/<team>/<product>/`** |

## Work-streams & rework inventory

Grounded in the current code. Effort is relative (S/M/L), not calendar.

| # | Stream | Today (reuse) | v3 rework | Effort | Where |
|---|---|---|---|---|---|
| **F1** | **v3 API + gitops layout** | XRD 303 ln (well-factored); Team CR git-native; gitops nascent | rename/re-scope XRD → `XEnvironment`; new `Product`/`AccessGrant` projected CRDs; `Service`/`Customer` schemas; new gitops dirs | **M** | `crossplane/charts/tenant`, `gitops/` |
| **L2a** | **Composition v3** | 534 ln go-template; ~40% (ns/quota/netpol/RBAC) is rename-only | ~50–60% rework: product-scoped ECR/IAM/Pod-Identity, ns + hostname derivation, image-scope, isolation-dial stubs | **M–L** | `crossplane/charts/tenant/files/composition-v2.yaml` |
| **L2b** | **Delivery (ADR-069)** | `argocd-apps` 420 ln; preview ApplicationSet (PR gen) reusable; `policy`/`github-oidc` keying | `argocd-apps` ~75% rewrite → **one ApplicationSet per Product** over (Env×Service); `policy` per-product keying (~30%); `github-oidc` per-Product roles (~20%) | **M–L** | `modules/argocd-apps`, `modules/policy`, `modules/aws/github_oidc` + their units |
| **L2c** | **Catalog projection (§10)** | `platform-projection` 393 ln + tests; emits System/Group/Resource | emit **System(Product)/Component(Service)/custom `Environment`/Group/Domain**; spanning selectors; re-home Resources | **M** | `backstage/plugins/platform-projection` |
| **L2c-fe** | **Frontend (§10)** | cards attach `kind=system`+ns-annotation (#285), `kind=group` (#34) | register `kind: Environment`; **re-point #285/#284 → `kind=Environment`**; Domain/Component pages | **S** | `backstage/packages/app/src/modules` |
| **L3a** | **Scaffolder: New Product + New Service** | `new-team`/`new-tenant`/`deprovision` templates; `verify-team-membership` action; **#371 App perm DONE** | new templates; **`github:repo:create`** (repo-on-demand, not yet used); a New-Product step | **S–M** | `scaffolder/templates`, `backstage/.../scaffolder` |
| **L3b** | **Multi-env starter** | `app-bravo` flat `k8s/preprod/`, hardcoded ns; thin-caller CI (build-sign + slsa) | `base/` + `overlays/<stage>/`; **remove hardcoded ns** (platform-injection); stage-picker seed | **S–M** | `app-bravo` (the generic starter) |
| **L3c** | **Promotion (P2, #377)** | starter `deploy.yml` already sed-bumps the digest + commits | digest-bump **PR bot**: auto-merge ≤ staging, **gated `release-approver` PR** for prod | **M** | new CI + the gate |
| **P4** | **Access model (#361)** | — | `AccessGrant` CRD+projection, Keycloak product-roles, OIDC cluster auth, `release-approver`/`team-admin`, 2-plane enforcement | **L** | parallel track (7 issues #362–368) |

## Dependency graph & build order

```text
        ┌─────────────────────────── F1: v3 API + gitops layout ───────────────────────────┐
        │  XEnvironment XRD · Product/Service/Customer/AccessGrant schemas · gitops dirs      │
        └───────────────┬───────────────────┬───────────────────┬──────────────┬────────────┘
                        ▼                   ▼                   ▼              ▼
                   L2a Composition     L2b Delivery        L2c Projection   P4 Access
                   (render-tested)     (render-tested)     (+ L2c-fe)       (parallel track)
                        └───────────────────┴───────────────────┘
                                            ▼
                            L3a Scaffolder · L3b Starter · L3c Promotion
                                            ▼
                            ══ REBUILD (cutover: deploy v3 from scratch) ══
```

**Phase 0 — foundation (serial, blocks everything):** **F1.** Land the `XEnvironment` XRD + the `Product`/
`AccessGrant` CRDs + the `Service`/`Customer` schemas + the new gitops layout, with **render tests** (the
`.tenant-api-tests` harness already exists). Nothing downstream can be built against a shape that doesn't exist.

**Phase 1 — the three readers (parallel after F1):** **L2a** (Composition), **L2b** (delivery), **L2c**
(projection + frontend). All read F1; independent of each other; all CI-render-tested, none deployed. This is the
bulk of the work and parallelizes cleanly across the platform repo (L2a/L2b) and the backstage repo (L2c).

**Phase 2 — developer-facing flows (after their reader):** **L3a** scaffolder (needs L2b delivery + L2c catalog
to land into), **L3b** starter (needs L2a's ns-injection contract), **L3c** promotion (needs L2b). L3b can
actually start early — it's just a repo refactor with low coupling.

**Phase 3 — the rebuild** deploys F1+L2+L3 from scratch and rolls the Backstage image. This is the existing
`platform-rebuild-from-scratch.md` runbook **plus the v3 deltas** (new gitops paths, the v3 XRD/Composition, the
rewritten units, the custom-kind catalog).

**P4 (access model)** is a **parallel track** — it only needs F1 (the `AccessGrant` CRD + projected CRs), then
proceeds on its own 7 issues; rebuild-gated deploy. Sequence it after Phase-1 starts, by a separate focus, or
fold its rebuild-gated pieces into Phase 3.

## Open design items to resolve (small, but they block their layer)

These are flagged in the schema doc's Open-questions and must close before the noted stream:

1. **New Product lifecycle** (gap #4) → blocks **L3a**. Does *New Service* create the Product (one repo : one
   product), or is there a separate *New Product* step? Small decision.
2. **Hostname under multi-service + customer** (gap #3) → blocks **L2a** hostname derivation + **L3b**. Extend
   ADR-060/061: `<service>-<product>-<team>-<stage>` + a customer component. Small–M design.
3. **Namespace 63-char ceiling** (gap #10) → blocks **F1**/L2a naming. A truncation/hash rule. Trivial but pin it.

Resolve 1–3 as the first task of (or just before) their layer — not up front, not as a surprise mid-build.

## Optional refactor (recommended, not required)

The agent surface-map flagged it and it pays off here: **split the `crossplane` module** — `tenant-xrd` (stable:
XRD + EnvironmentConfig) vs `tenant-composition` (iteration-heavy). The Composition will churn through L2a/L3c;
isolating it from the XRD improves CI feedback. Do it as part of F1 if cheap, else skip.

## Effort shape

- **Foundational + Phase-1 (F1 + L2a/b/c)** is the heavy middle — the platform repo's Composition + delivery
  rewrite and the backstage projection rewrite. This is where most of the build-cost lives.
- **Phase-2 (L3)** is lighter and mostly reuses existing scaffolder/CI machinery.
- **P4** is its own large track, decoupled.
- The **rebuild** is operationally heavy but procedurally known (the runbook exists; we add v3 deltas).

## Risks

- **v2 rework churn:** L2a/L2b rewrite code shipped only weeks ago (the A/B-tracks). Mitigation: it was never
  *deployed* (render-tested only), so this is editing branches, not migrating live state.
- **`argocd-apps` ApplicationSet-over-(Env×Service)** is the trickiest single piece (a matrix/git generator
  fan-out replacing per-resource Applications). De-risk it early with a spike on one product.
- **Custom `kind: Environment`** needs catalog registration + an EntityPage layout + re-pointed cards — verify
  the K8s/ArgoCD plugins attach to a custom kind by annotation (they should; confirm in L2c-fe).
- **Big-bang rebuild:** a lot is built before anything deploys. Mitigation: CI render-tests gate each stream;
  consider a throwaway rebuild on a sandbox to validate the v3 cutover before the real one.

## Issue map

F1 → new (XRD/schema); L2a → new (Composition); L2b → ADR-069 work (new); L2c → **#373**; L3a → **#372** (+ New
Product, new); L3b → **#376**; L3c → **#377** (P2); P4 → **#361** epic (#362–368). Umbrella **#369**.
