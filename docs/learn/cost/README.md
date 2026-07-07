# Learn: Cost & FinOps

How the platform turns cloud spend into an engineering signal — attributed per team, reconciled against the
real bill, optimized by live levers, and governed by budgets — all built into its own fabric, no cost SaaS.
A module organized on the **FinOps Foundation loop: Inform → Optimize → Operate**.

**Audience:** platform engineers, and any developer surprised by a cloud bill. **Before you start:**
[Observability](../observability/orientation.md) (cost is a signal in the same LGTM+P stack) and
[Foundations](../foundations/orientation.md) (the always-on cost drivers) help.

## Read in this order

1. **[Orientation](orientation.md)** — *"cost is an engineering signal, on a loop."* The one idea, the two-meter
   model (speedometer/odometer), and a tour of all three phases — with an honest "small in dollars; the point
   is the practice" framing and a status of what's built vs named.
2. **[Reference](reference.md)** — the dense lookup: the two meters, the CUR pipeline, the levers, the
   guardrails, the tool verdicts, the status ledger, gotchas.

## Go deep (one per FinOps phase)

- **[Inform — the two meters](deep-dive-inform-the-two-meters.md)** — OpenCost (list-price estimate) vs the
  CUR/Athena true-cost odometer, per-team attribution, the honestly-surfaced shared cost, the max-not-sum
  gotcha.
- **[Optimize — the cost levers](deep-dive-optimize-the-cost-levers.md)** — Karpenter consolidation, overnight
  cluster parking, the descheduler, the `cost_profile` toggle, and why Savings Plans are deferred (the parking
  tension).
- **[Operate — guardrails & the practice](deep-dive-operate-guardrails-and-the-practice.md)** — the per-team
  budget enforcer (surface → alert → enforce), AWS Budgets + Cost Anomaly Detection, and the ADR-092 FinOps
  operating model + tool verdicts.

## Then

- Where cost is collected + alerted: [Observability](../observability/orientation.md). The always-on drivers:
  [Foundations](../foundations/orientation.md). The team envelope's home: the
  [Domain model](../domain-model/orientation.md) (Team).
