# Learn: Cost & FinOps

How the platform turns cloud spend into an engineering signal: attributed per team, reconciled against
the real bill, optimized by live levers, and governed by budgets — all built into its own fabric, with no
cost SaaS. The module is organized on the FinOps Foundation loop: **Inform → Optimize → Operate**.

**Audience:** platform engineers, and any developer surprised by a cloud bill. It helps to have read
[Observability](../observability/orientation.md) first, since cost is a signal in the same LGTM+P stack,
and [Foundations](../foundations/orientation.md), which covers the always-on cost drivers.

## Read in this order

1. **[Orientation](orientation.md)** — cost as an engineering signal, on a loop. The one idea, the
   two-meter model (speedometer and odometer), and a tour of all three phases, framed honestly: small in
   dollars, but the point is the practice. Ends with a status of what's built versus named.
2. **[Reference](reference.md)** — the dense lookup: the two meters, the CUR pipeline, the levers, the
   guardrails, the tool verdicts, the status ledger, and the gotchas.

## Go deep (one per FinOps phase)

- **[Inform — the two meters](deep-dive-inform-the-two-meters.md)** — OpenCost as a list-price estimate
  versus the CUR/Athena true-cost odometer, per-team attribution, how shared cost is surfaced honestly,
  and the max-not-sum gotcha.
- **[Optimize — the cost levers](deep-dive-optimize-the-cost-levers.md)** — Karpenter consolidation,
  overnight cluster parking, the descheduler, the `cost_profile` toggle, and why Savings Plans are
  deferred (the parking tension).
- **[Operate — guardrails & the practice](deep-dive-operate-guardrails-and-the-practice.md)** — the
  per-team budget enforcer (surface → alert → enforce), AWS Budgets plus Cost Anomaly Detection, and the
  ADR-092 FinOps operating model with its tool verdicts.

## Then

- Where cost is collected and alerted: [Observability](../observability/orientation.md). The always-on
  drivers: [Foundations](../foundations/orientation.md). The team envelope's home: the
  [Domain model](../domain-model/orientation.md) (Team).
