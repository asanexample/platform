# Learn: Delivery — reference

Look-up, not a lesson. If you haven't built the model yet, read the [orientation](orientation.md) first.

## The mechanism, end to end

| Piece | What it is | Where |
| --- | --- | --- |
| **`Release` record** | the deployed **digest(s)** for one Environment — *the* source of truth for "what runs where" | `gitops/releases/<team>/<product>/<stage>.yaml` |
| **Per-Product ApplicationSet** | fans out over a Product's Releases → one ArgoCD `Application` per Release; injects the digest | `infra/modules/argocd-apps/delivery.tf` |
| **Auto-promoter** | cron reconciler that climbs the stage ladder, health-gated | `.github/workflows/auto-promote.yml` → `reconcile.sh` |
| **gitops Gate** | validates + auto-merges Release PRs (≤ staging); holds prod for a human | `.github/workflows/gitops-gate.yml` |
| **Argo Rollout** | the workload primitive — weighted-canary rollout of each digest | app repo `k8s/overlays/<stage>` |

## The Release record

```yaml
apiVersion: platform.refplat.org/v1beta1
kind: Release
metadata:
  name: alpha-shop-dev
spec:
  environmentRef: alpha-shop-dev          # <team>-<product>[-<customer>]-<stage>
  services:
    web:
      digest: sha256:f6b37d…              # the deployed image digest for this service, this stage
```

- One file **per Environment/stage**; a Service with no entry isn't deployed there.
- The digest is what deploys — **not** a tag. Immutable, content-addressed (see
  [Life of a Deployment](../spine/life-of-a-deployment.md) on why).
- Keyed on the **Release** (not the Environment) so a Product can deliver to more than one stage without a
  merge-key collision (ADR-071, #377).

## Delivery — the ApplicationSet

- **One ApplicationSet per Product**; a **git-files generator** fans out over `gitops/releases/<t>/<p>/*.yaml`
  → **one `Application` per Release**. An Environment with no Release yet generates **no** Application (no
  doomed `:placeholder` sync).
- The template derives stage (+ optional customer) from `spec.environmentRef`, points `source.path` at the
  app repo's `k8s/overlays/<stage>`, and a **`templatePatch`** injects the per-Service digest as a kustomize
  image override.
- **Sync policy:** `automated { selfHeal = true, prune = true }` + **ServerSideApply**. Self-heal reverts
  drift; prune deletes what git no longer declares.
- **Cross-account delivery:** one ArgoCD on the **hub** delivers to environment **spoke** clusters across the
  account boundary. **Design:** one spoke per account, with **prod in its own dedicated account/cluster**.
  **Built today:** one spoke — `preprod` (`argocd-clusters` registers `{preprod}` only). The prod account
  exists (networking only, no cluster), so *interim* every stage incl. `prod` lands as a namespace on the
  preprod spoke; it moves to its own account when the prod spoke is built. Reaches each spoke via a labeled
  cluster `Secret` carrying **AWS IAM auth** (the application-controller does STS AssumeRole + EKS token per
  target). The mechanism is generic over registered spokes.
- **Agents deliver to the hub** via a separate platform-agent ApplicationSet (`agents.tf`, ADR-082), not to
  the environment spokes.

## Promotion — how a digest climbs

Three producers, one output (an `asanexample-promote[bot]` Release PR that the Gate validates):

1. **On-demand — Backstage.** The **Request Promotion** scaffolder template resolves the source stage's
   digest and opens the target Release PR.
2. **On-demand — app repo.** `promote.yml` (a thin caller of the shared `trusted-ci` workflow) via
   `workflow_dispatch`, taking a `from_stage`; resolves the source digest post-clone.
3. **Automatic ≤ staging — `reconcile.sh` (cron).** Walks adjacent pairs `dev→test→uat→staging` (**prod
   excluded**). Per Service it: skips a rung already carrying the digest (**idempotent**); requires the
   upper Environment to **declare** that Service; and **gates on the lower stage's Application being
   `Synced + Healthy`**. So the digest climbs **one rung per run**, baking at each stage.

**The ladder:** `dev → test → uat → staging` auto (health-gated) → **`prod` gated by a release-approver**
(#501). Prod Release PRs never auto-merge.

## Progressive delivery — the Rollout

- **Every** environment workload is a direct-`spec.template` **Argo Rollout** (not a Deployment), on every
  stage — so prod is never the first place a Rollout runs (ADR-056).
- **Traffic shaping:** the Gateway-API traffic-router plugin (`argoproj-labs/gatewayAPI`) does **weighted
  HTTPRoute canary** on the Cilium Gateway — Rollouts edits the HTTPRoute weights, the data plane routes by
  weight (see [Life of a Request](../spine/life-of-a-request.md)).
- **Admission awareness (D2, ADR-056) — a real gotcha.** A `Rollout` isn't a `Deployment`, so the
  *workload-level* availability policies (replica-floor, PDB-generate, topology-spread) only match it when
  **`enable_rollout_kind = true`** is set per cluster (**default off** — a Kyverno rule can't name a CRD
  that's absent, so it's enabled only *after* the `argo-rollouts` unit is applied there, #7839).
  *Pod-level* policies (securityContext, preStop drain, cosign-verify) apply to Rollout pods automatically
  via ReplicaSet autogen. So a Rollout is admission-aware — but the availability mutations are an explicit
  opt-in, not free.
- **Status — be precise:** weighted-canary shifting is **built + live**; lower stages **auto-promote**
  through the steps (dogfooding); the fully **metric-gated `AnalysisTemplate`** (query Mimir → auto-rollback
  on an SLO breach) is **proven in mechanics, a later phase** — not the enforced default on every service
  yet.

## Gotchas that teach

- **`OutOfSync` with an empty diff.** A server-side-applied `Rollout`/`HTTPRoute` carries two field managers
  (argocd-controller + the rollouts-controller); ArgoCD's default client-side diff mis-reads it as drift.
  Fix with **server-side diff** (`controller.diff.server.side=true`, #925) — `ignoreDifferences`
  *can't* fix it.
- **A stuck promotion is usually correct.** The auto-promoter won't advance a rung while the lower stage
  isn't `Synced + Healthy`. That's the health gate, not a bug — fix the unhealthy lower stage.
- **Prod won't move on its own — by design.** No cron promotes into prod; it always waits on the
  release-approver.
- **The digest lives in the *platform* repo, not your app repo** — your `main` stays protected and
  CI-commit-free (ADR-071).

## Glossary

- **`Release` record** — a CR naming the deployed digest(s) for one Environment; the delivery source of truth.
- **ApplicationSet** — an ArgoCD controller that *generates* Applications from a data source (here, the
  Product's Release files).
- **Sync / self-heal / prune** — ArgoCD reconciling the cluster to git: apply desired, revert drift, delete
  the undeclared.
- **Rollout** — Argo Rollouts' Deployment-replacement that adds canary/blue-green + analysis.
- **Canary** — routing a *slice* of traffic to the new version first (weighted HTTPRoute here).
- **The ladder** — the ordered stages `dev → test → uat → staging → prod` a digest climbs.
- **release-approver** — the human role that must approve a **prod** Release PR (#501).

## Go deeper

- [Promotion & Release](../../architecture/promotion-and-release.md) (as-built) ·
  [ADR-021 ArgoCD](../../adrs/021-argocd-for-gitops.md) ·
  [ADR-069 delivery source-of-truth](../../adrs/069-delivery-source-of-truth-product-environment.md) ·
  [ADR-071 digest promotion](../../adrs/071-digest-promotion-via-control-plane.md) ·
  [ADR-056 progressive delivery](../../adrs/056-progressive-delivery-and-safe-rollback.md).
- The `argocd-app-delivery` house skill (ApplicationSets, PR previews, Release-keyed delivery).
- Substrate: [ArgoCD](https://argo-cd.readthedocs.io/en/stable/) ·
  [ApplicationSets](https://argo-cd.readthedocs.io/en/stable/user-guide/application-set/) ·
  [Argo Rollouts](https://argo-rollouts.readthedocs.io/en/stable/) ·
  [GitOps principles](https://opengitops.dev/).
