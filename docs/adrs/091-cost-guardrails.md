# ADR-091: Cost Guardrails — per-team budgets, attribution, and phased enforcement

**Date:** 2026-06-30

**Status:** Proposed

## Context

A credible internal developer platform treats **cost as a governed dimension**, not an afterthought. This
platform already has cost *visibility* — the [`observability-opencost`](../../infra/modules/observability-opencost)
module gives near-real-time per-team allocation, surfaced in Grafana — but it has **no guardrails**: no per-team
budget, no budget alerting, no enforcement, and no automation of the idle compute we currently reclaim **by
hand** (the nightly `platctl down` / morning `platctl up` park, [cluster-parking](../../.claude/skills/cluster-parking)).

The pieces a guardrail system needs already exist in the fabric:

- **The Team envelope** (`Team.spec.envelope`, ADR-063/067) — the per-team governance limits (`allowedTiers`,
  `allowedStages`, `quotaCap`). A team has a **resource** cap here; it has no **cost** budget. Cost belongs in
  the same envelope, declared once, projected everywhere — the model ADR-090 just reinforced for roles.
- **Attribution** — OpenCost allocates in-cluster spend by the `platform.refplat.org/team` label; the planned
  **CUR → Athena** path gives the authoritative cloud bill by cost-allocation tag.
- **Alert delivery** — the owner-routing + per-team PagerDuty/Slack fabric (ADR-084) already knows how to reach
  a team about *its* problem.
- **Levers** — the gitops gate (gates provisioning), `quotaCap` (caps resources), and Karpenter + `platctl`
  scale-to-zero (the park lever, ADR-078).

The gap is the connective tissue: a budget to measure against, the phased response, and turning the manual
park into a platform capability. This ADR proposes that model. **No hard enforcement is built by this ADR** —
it is audit-first by design (below).

## Decision

**D1 — A cost budget is a first-class part of the Team envelope.** Add `Team.spec.envelope.budget`
(`{ monthlyUSD: <number> }`, optional) — declared once in the Team CR, the same *decide-once-in-git,
project-everywhere* pattern as `quotaCap`. Absent budget ⇒ surfaced-but-unbounded (visibility, no guardrail).
Per-Product budgets are a later refinement; the Team is the first home.

**D2 — Attribution joins OpenCost (fast) and CUR→Athena (true), on the team tag.** OpenCost gives near-real-time
per-team allocation (compute/memory/storage/network) for the **trend/fast-feedback** loop; CUR→Athena gives the
authoritative monthly bill by cost-allocation tag for the **budget verdict** (it alone sees RI/Savings-Plan/
discount effects). The `team` label/tag is the join key. Allocation is the speedometer; CUR is the odometer.

**D3 — Guardrails are phased and audit-first** (the house pattern — Kyverno Audit→Enforce, the access deny-set):

- **Phase A — surface.** Per-team and per-Product cost in Grafana (dashboards-as-code) and a **Backstage cost
  tab**, so cost is visible where teams already work.
- **Phase B — alert.** **Budget burn-rate** alerts (projected month-end spend vs `budget.monthlyUSD` — e.g.
  on-track-to-overrun, or ≥80% consumed) routed via the ADR-084 owner-routing to the team's Slack/PagerDuty.
- **Phase C — enforce (gated soft brake).** Sustained over-budget ⇒ the gitops gate blocks **new** environment
  provisioning / quota increases for that team until addressed (with an admin override), and/or tightens
  `quotaCap`. It **never** evicts running workloads — stopping live traffic is the kill-switch, not a budget
  control.

**D4 — Idle automation: systematize the manual park.** Detect idle (off-hours + no traffic) → a surfaced
"**park to save ~$X**" recommendation → opt-in **auto-park** (scale node groups to zero via the existing
Karpenter/`platctl` path). This turns today's by-hand nightly park into a demonstrable, team-scoped capability.

**D5 — One source, projected — no parallel cost system.** The budget lives in the Team CR; OpenCost + CUR
*provide* spend; the dashboards, alerts, and gate are *projections*. Nothing to drift, nothing double-authored.

## Consequences

### Positive

- Cost becomes a governed dimension **like quota** — coherent with the envelope, not a bolted-on tool.
- **Audit-first** → safe rollout; teams see and are alerted on cost long before anything is enforced.
- The nightly hand-park becomes a **platform capability** (idle automation) instead of an operator chore.
- Reuses what's built — OpenCost, owner-routing, the gitops gate, Karpenter/`platctl`, the envelope — so the
  new surface is small.

### Negative / Risks

- **CUR lag.** The authoritative bill trails by hours-to-a-day; OpenCost allocation covers the fast loop but
  isn't the true bill (no discount awareness). Mitigation: trend on allocation, *verdict* on CUR.
- **Enforcement blast radius.** Phase C touching provisioning could block legitimate work — it MUST be a *gated
  soft brake with an override*, never a hard wall, and never touch running workloads.
- **Unattributable shared cost.** Control plane, gateways, observability, and the hub aren't team-attributable
  — they need an explicit **platform/shared bucket**, surfaced honestly, not silently socialized onto teams.

## Alternatives considered

- **A third-party FinOps platform** (Kubecost enterprise, CloudHealth, …) — rejected: we have OpenCost, and
  modeling cost in our own governance fabric *is* the demonstration; another vended control plane isn't.
- **Cost as a standalone system, separate from the envelope** — rejected: cost is a governance limit like
  quota; splitting it fragments the model (the exact incoherence ADR-090 just removed for roles).
- **Hard enforcement from day one** — rejected: audit-first is the house norm (surface → alert → enforce).
- **A cost/FinOps agent now** — deferred: an autonomous spend-watcher fits the `XAgent` runtime
  ([ADR-082](082-platform-agent-runtime-xagent.md)) *once* the budgets + surfacing exist for it to act on; it's
  a consumer of this model, not the first step.

## Related

- [ADR-063](063-team-as-first-class-git-object.md)/[ADR-067](067-idp-domain-model.md) (the Team + envelope this
  extends), [ADR-084](084-platform-identity-directory-and-owner-resolution.md) (owner-routing = the alert
  delivery), [ADR-078](078-cluster-elasticity-karpenter.md) (Karpenter = the park/scale-to-zero lever),
  [ADR-082](082-platform-agent-runtime-xagent.md) (a future cost agent).
- The `observability-opencost` module (in-cluster allocation) and the planned CUR→Athena true-spend path; the
  `cluster-parking` skill (the manual park D4 automates).
