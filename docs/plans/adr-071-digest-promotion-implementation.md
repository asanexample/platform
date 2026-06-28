# ADR-071 Implementation Plan — Control-Plane Digest Promotion (+ Gap #2 reconcile)

> **Status: DELIVERED — Release control-plane digest promotion is live. Retained for history.**

**Tracks:** [ADR-071](../adrs/071-digest-promotion-via-control-plane.md). **Forcing event:** the New Product
showcase (alpha/shop, 2026-06-14) — see [the showcase findings](../adrs/071-digest-promotion-via-control-plane.md#context).
**Goal:** app-repo `main` becomes fully-protected, CI-untouched application source; the deployed image digest
lives in the control plane and promotes via the existing gitops-Gate auto-merge. Bundles the showcase's second
finding (Gap #2: per-Product delivery plumbing needs a privileged `terragrunt apply`).

## Open decisions

1. **Record kind name — RESOLVED: `kind: Release`** (Josh, 2026-06-14). Avoids the apps/v1 `Deployment` collision;
   a "released digest-set per Environment." The ADR + schema + CRD are written to `Release`.
2. **Gap #2 mechanism — defaulting to (a), open to override.** (a) a **registry-reconcile CI job** that
   `terragrunt apply`s the 3 derived units on `gitops/products` changes (reuses existing units + the in-VPC ARC
   runners — pragmatic, ships fast), vs (b) **move the per-Product OIDC role + ApplicationSet +
   `verify-images-product` into the Crossplane Composition** (everything per-Product becomes auto-provisioned like
   ns/ECR/PodIdentity — cleaner, bigger). **Proceeding with (a) now, (b) as a later convergence** (Workstream 2).

---

## Workstream 1 — Control-plane digest promotion

### PR 1 — Schema: the per-Environment `Release` record

- **Add** the control-plane record shape to `docs/architecture/platform-domain-api.md` and a projected CRD in
  `infra/modules/crossplane/charts/environment-api/` (`release-crd.yaml`, `platform.refplat.org/v1beta1`,
  cluster-scoped, named `<team>-<product>-<stage>[-<customer>]`). Shape: `spec.environmentRef` +
  `spec.services.<svc>.digest`.
- **Layout:** `gitops/releases/<team>/<product>/<stage>[-<customer>].yaml` (CI-owned), sibling to the
  human-owned `gitops/environments/…` claim.
- **Validate:** add `.environment-api-tests` fixtures (valid/invalid digests, dangling environmentRef) → extend
  `run.sh`.
- *Files:* `platform-domain-api.md`, `charts/environment-api/templates/release-crd.yaml`,
  `.environment-api-tests/**`. *No cluster.*

### PR 2 — gitops Gate validator for `Release`

- **`validate-releases.sh`**: each changed `gitops/releases/**` file is digest-only vs base, references an
  existing `Environment`+`Service` (join against `gitops/environments` + the Product's `services`), the digest's
  image is in the Product's ECR scope (`team-<team>/<product>-<svc>`), and (stretch) a cosign attestation exists.
- **`classify-diff.sh`**: recognize `gitops/releases/**` → route to the auto-merge path (bot-authored +
  release-only + non-deletion), mirroring the registry-only path (#417).
- **Validate:** `test-validate-releases.sh` fixtures across PR shapes.
- *Files:* `.github/scripts/gitops-gate/{validate-releases.sh,classify-diff.sh}`, `gitops-gate.yml`.

### PR 3 — The `promote` reusable workflow + a promote GitHub App

- **`asanexample/trusted-ci/.github/workflows/promote.yml`** (app-team-unwritable, like `build-sign.yml`):
  inputs `team/product/stage/customer?/service/digest` → checks out the platform repo → bumps
  `gitops/releases/<…>.yaml` → opens a gated PR (auto-merged by PR 2's path). Authenticated as a **promote
  GitHub App** scoped to open PRs on `asanexample/platform` only — **no write to any app `main`.**
- **Manual prereq (operator):** create the promote GitHub App + its secret (a runbook, like
  `arc-github-app.md`).
- *Files:* `trusted-ci` repo workflow; `docs/runbooks/promote-github-app.md`; the App's Secrets-Manager secret.

### PR 4 — ApplicationSet injects the digest

- The per-Product ApplicationSet (`infra/modules/argocd-apps/delivery.tf`) gains a **merge generator**
  (environments × releases over the platform repo) and a **kustomize image override** patch that sets the
  service image to the `Release` digest — alongside today's ns + host patch. The app overlay stays
  `:placeholder`; **whatever the `Release` records deploys** (ADR-071 §3).
- **Validate:** cluster-only (ApplicationSets have no offline test) — verify on preprod with alpha-shop.
- *Files:* `infra/modules/argocd-apps/delivery.tf`. *Apply via `terragrunt apply` (or Gap #2 reconcile once it
  lands).*

### PR 5 — Starters + app CI switch to promote; migrate the live apps

- **Scaffolder starters** (`scaffolder/templates/new-product/skeleton-*/.github/workflows/deploy.yml` + each
  `k8s/overlays/*`): the deploy job **calls `promote.yml`** instead of self-pinning; overlays ship
  `:placeholder`.
- **Migrate** `app-alpha`, `app-bravo`, `app-alpha-shop` to the new `deploy.yml`; **re-protect
  `app-alpha-shop/main`** (the showcase unblock left it unprotected — ADR-071 Consequences).
- *Files:* scaffolder skeletons; the 3 app repos.

### PR 6 — Flip ADR-071 → Accepted; remove the interim mechanism

- ADR-071 status → Accepted; update `platform-domain-api.md` (drop the "digest in app overlay" interim note);
  retire the self-overlay-pin guidance.

---

## Workstream 2 — Gap #2: per-Product delivery-plumbing reconcile

Today a new Product's per-Product **OIDC ECR-push role** (`github-oidc`), **ApplicationSet** (`argocd-apps`), and
**`verify-images-product` policy** (`policy`) are `fileset`-derived from `gitops/products` → they don't exist
until a privileged `terragrunt apply`. The showcase needed all three applied by hand.

### Option (a) — registry-reconcile CI job (recommended first step)

- **PR 7a:** a workflow that, on merge to `main` touching `gitops/products/**`, runs `terragrunt apply` on
  `github-oidc` + `argocd-apps` + `policy` on the **in-VPC ARC self-hosted runners** (they already hold cluster +
  PlatformDeployer access). Sequential, gated, idempotent. Closes the seam with no model change.
- *Files:* `.github/workflows/registry-reconcile.yml`; ARC runner perms.

### Option (b) — move per-Product plumbing into the Composition (later convergence)

- **PR 7b–9b:** add the per-Product OIDC role (provider-aws IAM), the ApplicationSet (provider-kubernetes), and
  `verify-images-product` (provider-kubernetes ClusterPolicy) to the Crossplane Environment/Product Composition,
  so they auto-provision like the rest of the footprint. Eliminates Terragrunt-derived per-Product resources.
  Larger; do after Workstream 1 proves the control-plane delivery path.

---

## Sequencing & dependencies

```text
PR1 (schema) → PR2 (gate) → PR3 (promote wf) → PR4 (appset inject) → PR5 (starters+migrate) → PR6 (accept)
                                   └ Gap#2 PR7a (reconcile) can land in parallel after PR4 (unblocks auto-apply)
```

PR 1–2 are pure additions (no behavior change). PR 4 is the first cluster-affecting change. PR 5 is the cutover
(apps stop self-pinning). PR 7a removes the manual `terragrunt apply` the showcase needed.

## Migration / rollback

- Until PR 5, apps keep self-pinning (the interim mechanism still works on unprotected mains). PR 4's injection is
  additive — if no `Release` exists, the overlay `:placeholder` simply doesn't resolve (App OutOfSync, harmless),
  so PR 4 before PR 5 is safe.
- Rollback of a bad deploy = revert the `Release` digest line (a control-plane PR), not an app-repo change.

## Validation gates

- PR 1/2: schema + gate test harnesses (offline). PR 3: dry-run promote PR. PR 4/5: live on preprod via alpha-shop
  (pod runs the injected digest; app `main` receives zero CI commits; re-protected). PR 7a: a `gitops/products`
  PR triggers the reconcile → the new Product's role/AppSet/policy appear with no human apply.
