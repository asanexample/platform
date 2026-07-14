# Learn: Delivery

How a built, signed image becomes a *running* workload across every stage — via GitOps, a health-gated
promotion ladder, and progressive (canary) rollout. This zooms in on the middle of
[The Life of a Deployment](../spine/life-of-a-deployment.md).

**Audience:** platform engineers who operate or extend delivery. Developers only need the "2-minute view" at
the end of the orientation. Already fluent in ArgoCD + Argo Rollouts? Skip to the [Reference](reference.md).

**Before you start:** the [domain model](../domain-model/orientation.md) (Product / Environment / Stage) and
ideally [Life of a Deployment](../spine/life-of-a-deployment.md).

## Read in this order

1. **[Orientation](orientation.md)** — the one idea (*you move a digest up a ladder; reconcilers converge each
   rung*), the three reconcilers (auto-promoter · ArgoCD · Rollout), and a real `acme-shop` climb from dev to
   prod.
2. **[Reference](reference.md)** — look-up: the `Release` schema, the per-Product ApplicationSet, the
   promotion paths and the ladder, the Rollout canary, the gotchas that bite, and a glossary.

## Then, to go deeper on the real system

- The end-to-end flow: [The Life of a Deployment](../spine/life-of-a-deployment.md) · the runtime side:
  [The Life of a Request](../spine/life-of-a-request.md).
- Architecture: [Promotion & Release](../../architecture/promotion-and-release.md).
- Extend it: the `argocd-app-delivery` house skill.
