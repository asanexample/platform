# ADR-071: Image-Digest Promotion via the Control Plane (Protected-Main Delivery)

**Date:** 2026-06-14

**Status:** Accepted + **IMPLEMENTED & PROVEN LIVE** (2026-06-15) — the full chain works end-to-end on
`app-alpha-shop`: app deploy → build-sign → `promote.yml` (as the `asanexample-promote` App) opens a gated
Release PR on the platform repo → the gitops Gate auto-merges it → the per-Product ApplicationSet injects the
digest → the pod rolls, **with the app repo's `main` receiving zero CI commits** (now re-protected). Delivered via
`charts/applicationset-raw` (B-via-Helm — `kubernetes_manifest` cannot represent ArgoCD's recursive `merge`
generator). PRs: Release schema/gate (#445/#446), promote App + recognition (#447, trusted-ci#12/#13),
registry-reconcile (#448), ApplicationSet injection (#451), scaffolder starter (#453). **Resolves the
P2/[#377](069-delivery-source-of-truth-product-environment.md) decision
deferred by [ADR-069](069-delivery-source-of-truth-product-environment.md) §4** ("where the digest lives and how
it is promoted should not be locked in by the delivery layer"). ADR-069 already names the deployed **digest** an
**Environment-owned fact** (§2, *one home per fact*); this ADR decides its *home* and *promotion mechanism*. Also
refines the self-service flow of [ADR-062](062-self-service-tenant-provisioning.md). Implementable incrementally
(not rebuild-gated).

## Context

The interim delivery mechanism (ADR-069 §4) is: *"whatever digest is committed in the app overlay deploys — apps
already commit their digest to their own overlay today, so nothing breaks meanwhile."* Each app repo's
`deploy.yml` builds + cosign-signs + pushes its image, then **pushes a commit pinning the digest into its own
`k8s/overlays/<stage>/kustomization.yaml` on `main`.**

The **New Product self-service showcase** (alpha/shop, 2026-06-14) ran this end-to-end for the first time on a
freshly-scaffolded repo and exposed the flaw. Backstage's `publish:github` protects the default branch by default
(`protectDefaultBranch: true`, `enforce_admins: true`), so the `deploy.yml` digest-pin push to `main` was
rejected:

```text
remote: error: GH006: Protected branch update failed for refs/heads/main
```

The only reason this never surfaced before is that the **existing demo app repos (`app-alpha`, `app-bravo`) have
*unprotected* `main`** — the digest-pin works there precisely because nothing guards it. Disabling protection to
make CI's push succeed is the wrong trade: app source *should* be protected.

**Root cause — source/state conflation.** The app repo holds two things with opposite governance needs in one
place:

| Fact | Owner | Cadence | Wants |
| --- | --- | --- | --- |
| application **source** | humans | per feature | PR + review + protection |
| deployed image **digest** | CI | per build | automated, frequent writes |

Branch protection guards the first; the digest-pin needs to write the second. They collide because the digest
(*desired deployed state*) is being stored in the *source* repo. ADR-069's "one home per fact" already says the
digest belongs to the **Environment** — i.e. the **control plane (the platform repo)** — not the app's source.
The interim "digest in the app overlay" was explicitly temporary; the showcase is the forcing function to finish
it.

A second seam surfaced in the same showcase (the per-Product **OIDC push-role**, **ApplicationSet**, and
**`verify-images-product` policy** are Terraform-derived from the registry and required a privileged
`terragrunt apply` before the new Product could build or deploy). It is **out of scope here** but shares the root
principle — *the platform repo is the delivery control plane* — and should be designed in the same epic (see
*Related work*).

## Decision

**The deployed image digest is Environment state and lives in the platform (control-plane) repo. App-repo `main`
is application source only — fully protected, human-PR-only, never written by CI. Promotion is a gated PR to the
control plane, merged by the existing gitops-Gate auto-merge.**

### 1. Digest home — a per-Environment `Release` record, separate from the claim

The digest lives in a dedicated control-plane file (`kind: Release`), **not** in the human-owned `XEnvironment`
claim:

```text
gitops/releases/<team>/<product>/<stage>[-<customer>].yaml      # CI-owned, digest-per-service
gitops/environments/<team>/<product>/<stage>[-<customer>].yaml  # human-owned XEnvironment claim (unchanged)
```

```yaml
# gitops/releases/alpha/shop/dev.yaml  — owned by CI, one digest per service
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata: { name: alpha-shop-dev }
spec:
  environmentRef: alpha-shop-dev
  services:
    web: { digest: "sha256:69ff1ab2…" }
```

Keeping it **separate from the claim** matters: the claim is envelope-validated, rarely-changing, human-owned;
folding a per-build digest into it would churn the claim file on every deploy and force the heavyweight envelope
gate to re-run for a one-line image bump. Separate homes keep each object's gate, cadence, and ownership clean
(this is "one home per fact" applied *within* the control plane).

### 2. Promotion = a gated PR to the control plane (reuses existing machinery)

The app CI stops pushing to its own `main`. Instead, after build+sign+push, it opens a PR against the **platform
repo** bumping `gitops/releases/<…>.yaml`. This is **not new machinery** — it is the same path that merged the
showcase's onboarding PR:

- The **gitops Gate** ([ADR-069 §3](069-delivery-source-of-truth-product-environment.md) / #388) validates the
  change (digest-only, references an existing Environment+Service, signature attested) and **auto-merges**
  bot-authored, registry-only, non-deletion PRs ([ADR-062](062-self-service-tenant-provisioning.md) /
  #417) — exactly the shape of a digest bump.
- A platform-owned **reusable "promote" workflow/action** opens the PR so app repos stay thin (consistent with
  [ADR-050](050-shared-build-sign-reusable-workflow.md)'s shared, app-team-unwritable supply-chain backbone).
  App repos never need write access to any `main`.

### 3. The ApplicationSet injects the digest; the app overlay stays a placeholder

The per-Product ApplicationSet (ADR-069 §3) already injects per-Environment namespace + host via a kustomize
patch. It additionally **reads the digest from `gitops/releases/…` (its git generator already walks the
platform repo) and injects it as a kustomize image override.** The app overlay keeps `:placeholder` — **CI never
pins it**, so the app repo's `k8s/` is pure, environment-agnostic source. *Whatever digest the control plane
records deploys* — the same contract as ADR-069 §4, with the home corrected from app-overlay to control-plane.

> **Correction (#377): the generator is release-keyed.** The first implementation joined the Environment claim
> to its Release with a `merge` generator keyed on `path.basenameNormalized`. Under `goTemplate` every manifest
> field nests, so that dotted key resolved to `null`; a second Environment for the same Product collided on the
> `{null}` key and broke the *whole* ApplicationSet — no Product could deliver to more than one stage. The
> generator now fans out over the **Releases** alone (one Application per `gitops/releases/<t>/<p>/*.yaml`),
> deriving stage/customer from `spec.environmentRef` and team/product from the Terraform loop. No merge key, no
> collision. An Environment with no Release simply generates no Application (its first promote creates one).

### 4. App-repo `main` is protected by default

The New Product scaffolder keeps `publish:github`'s default-branch protection (require PR + review). Because CI
no longer writes to app `main`, protection needs **no bypass actor** — the entire "automated-commit-to-protected-
main" problem is dissolved rather than carved around.

## Consequences

### Positive

- **App-repo `main` is fully protected, human-PR-only, with zero CI write access** — no bypass actor, no
  enforce-admins hole. The trust surface shrinks: a compromised app-CI token cannot rewrite app source.
- **Source and deployed-state are correctly separated** (app repo = source; control plane = desired state) —
  the textbook GitOps split, and the platform's own *registries-as-single-source* philosophy
  ([ADR-061](061-tenant-ingress-and-custom-domain-strategy.md)/[ADR-067](067-idp-domain-model.md)).
- **Reuses proven machinery** — the gitops Gate + admin-gated auto-merge already performs gated writes under
  branch protection; promotion rides it instead of inventing a per-app mechanism.
- **This *is* promote-by-PR (#377), realized at the right layer.** A/B would be throwaway work #377 later
  replaces; this completes #377.
- **Auditable + reversible** — every promotion and rollback is a control-plane PR with the signed-image attestation
  in scope; rollback = revert the digest line.

### Negative / costs

- **Largest change of the three options.** Touches: the New Product scaffolder, the shared `trusted-ci` deploy
  flow (emit digest + open promote-PR instead of self-push), the per-Product ApplicationSet (inject digest), the
  gitops Gate (a `Release` record validator), and the `platform-domain-api` schema (the `Release` kind).
- **A promotion is now two repos** (image pushed to ECR by the app; digest recorded in the platform repo). Mildly
  less local for app developers, but it is the correct boundary.
- **Migration:** `app-alpha`/`app-bravo` move off self-overlay-pinning to control-plane promotion;
  `app-alpha-shop` re-protects `main` once the promote path lands (it is temporarily unprotected from the
  showcase unblock — tracked).

## Alternatives considered

- **A. Protected ruleset + CI-App bypass actor.** Protect `main` but list a CI GitHub App as a ruleset bypass so
  `deploy.yml` keeps pushing the digest directly. *Rejected as the target architecture:* it preserves the
  source/state conflation and keeps a CI identity that can write to app `main` (a standing trust surface that
  partially defeats protection). **Acceptable only as a deliberate, documented tactical bridge** if protected-main
  app deploys are needed before this ADR lands — it is debt this ADR removes.
- **B. Auto-merged digest PR in the app repo.** `deploy.yml` opens a digest PR against the app's own `main`,
  auto-merged by a bot. *Rejected:* more auditable than A but still writes deployed-state into the source repo and
  still needs a merge/bypass identity on every app — it is A with ceremony, not a structural fix.
- **C (chosen).** Digest in the control plane; app `main` CI-untouched.

## Related work

- **Per-Product delivery-plumbing apply seam** (the showcase's other finding): the OIDC push-role, ApplicationSet,
  and `verify-images-product` policy are Terraform-derived from `gitops/products` and require a privileged
  `terragrunt apply` per new Product, blocking first build + deploy. Same root principle (control plane owns
  delivery); candidate fixes — a registry→Terragrunt reconcile job, or moving these into the Crossplane
  Composition like the rest of the Environment footprint — belong in the same epic as this ADR.
- Supersedes the interim digest mechanism of
  [ADR-069 §4](069-delivery-source-of-truth-product-environment.md); shares the gated-auto-merge path with
  [ADR-062](062-self-service-tenant-provisioning.md); keeps the thin-app-CI posture of
  [ADR-050](050-shared-build-sign-reusable-workflow.md).
