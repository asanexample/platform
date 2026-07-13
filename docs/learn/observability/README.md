# Learn: Observability

How the platform sees itself — how a slow request, a crash loop, or a runaway LLM bill becomes findable, and
how little a team has to do to make it so. A whole-picture tour, then focused deep dives.

Written for platform engineers and any developer who's debugged from a dashboard. Most of it is
platform-injected, so a developer gets the payoff without the plumbing. It helps to have read
[Foundations](../foundations/orientation.md) (the cluster this runs on) and
[Delivery](../delivery/orientation.md), and to know roughly what a metric, a log, and a trace are.

## Read in this order

1. **[Orientation](orientation.md)** — the one idea, "the platform observes your workload for you," and a tour:
   the four signals → zero-code collection (Beyla eBPF) → the self-hosted LGTM+P stack → correlation (the jump)
   → acting on signals (SLOs, pages, cost) → observing the agents. Includes a straight status of what's live and
   what's deferred: per-team isolation is enforced hub-first, and traces/profiles isolation is deferred.
2. **[Reference](reference.md)** — the dense lookup: versions, the stack, tenancy, the collectors, SLOs/alerts/
   cost, agent-obs, the status ledger, gotchas.

## Go deep

- **[The stack & storage](deep-dive-the-stack-and-storage.md)** — the LGTM+P backends, S3, Grafana + SSO, the
  `X-Scope-OrgID` tenancy model (and why isolation is really the network), hub-and-spoke, and why self-hosted.
- **[Collection & instrumentation](deep-dive-collection-and-instrumentation.md)** — every collector, the eBPF
  zero-code story (Beyla), the instrumentation ladder (Layer 0/1/2), and platform-injection.
- **[Correlation & the team experience](deep-dive-correlation-and-the-team-experience.md)** — the
  metrics↔traces↔logs↔profiles jumps, the per-team overview dashboards, and the honest per-team-isolation story.
- **[SLOs, alerting & cost](deep-dive-slos-alerting-and-cost.md)** — burn-rate SLOs, curated alerts +
  triage-agent owner-routing, and cost-as-a-signal (OpenCost + true-cost).
- **[Agent observability](deep-dive-agent-observability.md)** — the OTel GenAI semantic conventions, the agent
  span tree, and the human-verdict eval loop.

## Then

- The substrate it runs on: [Foundations](../foundations/orientation.md). The alert-routing agent:
  [Identity & access](../identity/orientation.md) (owner resolution). Author obs: the `observability-authoring`
  skill.
