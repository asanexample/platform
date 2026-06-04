# ADR-056: Progressive Delivery & Safe Rollback

**Date:** 2026-06-04

**Status:** Proposed — **strategy/direction.** Adds health-gated, automatically-reversible prod rollouts on top
of the existing GitOps delivery ([ADR-021](021-argocd-for-gitops.md)) and PR preview environments
([ADR-032](032-pr-preview-environments.md)). Consumes the SLO/error-budget contract from
[ADR-054](054-platform-resilience-and-business-continuity.md) and the developer-access separation-of-duties from
[ADR-049](049-tenant-model-team-tenant-zone.md)/[ADR-040](040-platform-engineer-access-model.md). Uses the
Gateway API ([ADR-017](017-gateway-api-over-ingress.md)) for traffic shaping.

## Context

Delivery is GitOps (ArgoCD) with ApplicationSet **PR previews** — strong for the inner loop. But a **prod
rollout is a plain ArgoCD sync**: the new version replaces the old with no canary, no health-gated promotion,
and **no automatic rollback**. A bad deploy to prod is caught by humans, after impact. Regulated prod in
particular needs progressive, automatically-reverted rollouts with separation of duties (deployer ≠ approver),
and the per-tier **error budgets** (ADR-054) currently have no rollout to gate.

## Decision

1. **Argo Rollouts for prod workloads.** It integrates natively with ArgoCD and the Gateway API the platform
   already runs. Canary or blue-green per workload; **analysis steps query the observability stack**
   (Prometheus/Mimir) as health gates; **automatic rollback on breach.**
2. **The rollout strategy is a tier/env property, not per-app guesswork.** preprod = fast/permissive; **prod /
   standard** = canary with metric gates; **prod / regulated** = canary + a **manual approval gate** + audit
   (the separation of duties from ADR-049: the approver is not the deployer).
3. **Error budgets gate change velocity.** The tier availability SLO (ADR-054) defines the budget; **budget
   exhaustion freezes non-critical rollouts** until it recovers.
4. **No service mesh required** — L7 canary uses Gateway API / HTTPRoute weighting (Cilium Gateway). A mesh is
   revisited only if *east-west* (service-to-service) canary is needed (cross-ref
   [ADR-057](057-service-identity-and-east-west-zero-trust.md)).

## Alternatives considered

- **Flagger.** Comparable capability, but Argo Rollouts is closer to the existing ArgoCD + Gateway API stack.
  Rejected on fit, not merit.
- **Manual canary via two ArgoCD apps + weighted routes.** No automated analysis or rollback — it's the status
  quo with extra steps. Rejected.
- **Keep plain sync.** Acceptable for preprod, unsafe for regulated prod. Rejected as the prod default.

## Consequences

- Materially safer prod, with **auditable approval gates** for regulated rollouts.
- **Couples delivery to observability** — rollouts need reliable metrics, so this depends on the SLO/metrics
  work landing first.
- Adds a **Rollout** resource to tenant manifests — the Kyverno authoring rules and the Tenant `apps` delivery
  path must accommodate it (and Rollout pod specs are still subject to the same admission policies).
- **Open:** the default analysis templates (which metrics, thresholds) per tier.
