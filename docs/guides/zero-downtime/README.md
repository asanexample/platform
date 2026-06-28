# Zero-downtime deployments

This platform deploys application changes **without dropping traffic** — and, in production,
**without shipping a bad version to all of your users**. It does this with two interlocking layers
that apply to every environment workload automatically:

1. **Availability defaults** ([ADR-085](../../adrs/085-workload-availability-graceful-disruption-defaults.md)) —
   graceful connection draining, a PodDisruptionBudget, topology spread, and a production replica
   floor, all injected for you. This keeps traffic flowing through pod restarts, node consolidation,
   cluster upgrades, and scaling events.
2. **Progressive delivery** ([ADR-056](../../adrs/056-progressive-delivery-and-safe-rollback.md)) —
   every workload is an **Argo Rollout**. Production changes roll out as a **metric-gated canary**
   that promotes only while real traffic stays healthy and **rolls back automatically** if it
   doesn't, and a **pre-flight error-budget freeze** that refuses to deploy into an already-unhealthy
   service.

Together: a deploy shifts traffic gradually, watches live SLO metrics, and reverses itself on harm —
while the underlying pods drain gracefully and never all disappear at once.

## Start here

| You are a… | Read |
|---|---|
| **Developer** shipping an app | [Zero-downtime deployments for developers](overview-developers.md) — what's automatic, what's yours, how to watch a rollout |
| **Platform engineer** operating/extending the system | [Zero-downtime deployment internals](overview-platform.md) — the full mechanism, component by component |
| Anyone wanting the **architecture** | [Architecture](../../architecture/zero-downtime-deployments.md) — components, flows, diagrams, the decision map |
| Looking for the **decisions / "why"** | ADRs [085](../../adrs/085-workload-availability-graceful-disruption-defaults.md) (availability), [056](../../adrs/056-progressive-delivery-and-safe-rollback.md) (progressive delivery), [054](../../adrs/054-platform-resilience-and-business-continuity.md) (resilience/SLOs), [049](../../adrs/049-tenant-model-team-tenant-zone.md) (separation of duties) |

## What you get, by stage

| Stage | Rollout strategy | Gates |
|---|---|---|
| dev / test / uat / staging | trivial auto-promoting canary (`setWeight: 100`) | none — fast feedback |
| **prod (standard)** | **stepped canary** 25 → 50 → 100% | **pre-flight error-budget freeze** + **background metric gate** (auto-rollback) |
| prod (regulated) | + manual approval gate (deployer ≠ approver) | *deferred — [#908](https://github.com/asanexample/platform/issues/908)* |

## Status

Live on both clusters: availability defaults (enforced), Rollouts-everywhere, the Gateway-API
weighted canary, the background metric gate with auto-rollback, per-app SLOs, and the error-budget
freeze. Deferred: the regulated-tier manual gate (W10). See the
[architecture doc](../../architecture/zero-downtime-deployments.md#as-built-status) for the precise
as-built breakdown.

> **Scope of these docs (Phase 1).** This set covers *how it works* (both audiences) + the
> architecture. Task guides (ship a canary, roll back, add a gate), reference tables, runbooks, and a
> demo walkthrough are planned follow-ons.
