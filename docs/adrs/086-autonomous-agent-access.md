# ADR-086: Autonomous Agent Access — Graduated Autonomy under Machine-Enforced Guardrails

**Status:** Proposed (draft / sketch — 2026-06-27)

> **Extends [ADR-074](074-agentic-workloads-platform.md).** ADR-074 made agents a governed workload class
> but pinned tier-0 to **propose-only / zero-privilege / human-gate**, while explicitly *designing-for*
> autonomy and flagging its `auto-policy-gate` as "the autonomy seam… under-specified… needs its own
> rigorous design." This ADR is that design: the access model that lets selected agents act **autonomously
> and safely**. It changes **none** of ADR-074's safety invariants; it specifies the seam ADR-074 left
> open. Workforce-side companion: [identity-and-access-strategy](../architecture/identity-and-access-strategy.md) §3.4.

## Context

ADR-074's propose-only posture is the right *floor* — it proved the substrate at minimal risk. But it is
not the *ceiling*. A fully-featured agent developer platform needs agents that can **act**, not only
suggest — e.g. **real-time remediation** of alerts (restart a wedged pod, scale to absorb load, roll back a
bad deploy, drain a stuck queue) where waiting for a human approval defeats the purpose.

The two naive options are both wrong:

- **Propose-only forever** — safe, but caps the platform's value; an agent that can only open a PR cannot
  auto-remediate at 3am.
- **Give a trusted agent broad `operate` access** — powerful, but unsafe: no bounded blast radius, and a
  prompt-injected agent holding standing operate is the single worst case in the whole system.

So we need the middle: **more permissive than propose-only, but with the human gate replaced by
machine-enforced guardrails trustworthy enough to stand in for it** — applied only where the risk is
acceptable.

The central reframe: **"more permissive" must not mean "fewer guardrails." It means moving the guardrail
from a human-in-the-loop to machine-enforced bounds.** Safety does not decrease; it *changes shape* — from
a person approving each action to a policy authorizing it against tight, reversible, proven bounds.

## Decision

**Autonomy is graduated, per-action-class, earned, and machine-bounded — never a global property of an
agent.** An agent may act autonomously on an action-class **only when all** of these hold; otherwise the
action stays gated (ADR-074 unchanged):

1. the class is inside the agent's **explicit capability envelope** (an allow-list, not "operate");
2. the class is **reversible or bounded-impact** (the license for autonomy);
3. each action is **authorized by machine policy at action-time** against the envelope, the live-caller
   intersection (ADR-074), and the reversibility/risk classification;
4. the agent is within its **rate / budget / circuit-breaker** limits;
5. the agent has **earned** autonomy on that class through evaluation (shadow → proven → promoted).

ADR-074's safety invariants remain **non-configurable**: a named human sponsor + accountability, the
kill-switch, injection defense by provenance separation, and zero standing privilege beyond the granted
envelope. Autonomy unlocks **only behind ADR-074's maturity prerequisites** (eval-as-a-service +
kill-switch) — it is a post-tier-0 capability.

## The design

### Autonomy tiers — specifying ADR-074's `auto-policy-gate`

Disposition becomes a per-action-class spectrum, keyed to **risk × reversibility**:

- **autonomous** — reversible / bounded-impact, in-envelope, policy-authorized; runs with no human;
- **human-gated** — significant / irreversible (ADR-074's existing gate);
- **multi-human-gated** — high-stakes / regulated.

The agent never self-selects its tier; the platform's classification does.

### Reversibility classification — the crux

The hardest, most safety-critical piece. Every autonomy-eligible action-class is classified by
**reversibility × blast radius** in a **platform-owned classification registry** (never author- or
agent-set):

- **reversible / self-limiting** (restart pod, scale within bounds, roll back to known-good, requeue) →
  autonomy-eligible;
- **irreversible / unbounded** (delete data, mutate prod config/secrets, widen access, spend money) →
  never autonomous.

Misclassification is the dominant risk — an autonomous agent does machine-speed damage before a human
notices — so classification is **conservative-by-default**, reviewed like policy, and a class is
autonomy-eligible **only by explicit listing**.

### Capability envelope

The `Agent` spec (ADR-074) gains a bounded, Kyverno-validated **action allow-list**: each entry is
`(action-class, target-scope, mode)` where `mode ∈ {propose, autonomous}`, and `autonomous` is admissible
only for a registry-reversible class. Changing it is a gated, elevated-review PR (the envelope is a control
surface).

### Action-time enforcement — ADR-074's deferred admission surface, at runtime

A **policy decision at the action boundary** (the trusted code ADR-074 names) authorizes each autonomous
action *before it executes*: in-envelope? class autonomy-eligible? within the live-caller intersection?
within limits? A deny falls back to propose + gate. This is the runtime counterpart to the admission policy
ADR-074 deferred — kept **at the trusted boundary, not a central engine the agent calls** (preserving the
"no central PDP" stance).

### Circuit breakers, budgets, rate limits

Autonomous agents loop, so they are capped: per-class rate limits, action budgets, anomaly tripwires, and a
breaker that **halts the agent and falls back to the deterministic / gated path** — wired to the global
kill-switch (ADR-074).

### Earned autonomy — graduation

An agent does not start autonomous on a class. It **graduates**: **shadow** (proposes; the system records
what it *would* have done and whether that was right) → **measured reliability** (eval-as-a-service,
threshold by tier) → **promoted** to autonomous on that class; **demoted automatically on regression.**
Autonomy level per class is part of the agent's **versioned, signed release** (ADR-074's composite
version).

### Reversibility tooling, audit, accountability

Every autonomous action is **logged, attributable to agent + sponsor, and paired with an undo path** where
the class allows; fast rollback + kill remain. Online outcome signals (did the remediation hold?) feed back
into evaluation.

### Injection defense rises with power

A more-capable agent is a bigger injection target, so the bar **goes up**: provenance separation (signed
system prompt vs. untrusted conversation / alert / log data) and the context-as-data boundary are hard
requirements; higher-autonomy agents get stricter egress and data-class limits. The incident/alert content
an auto-remediation agent consumes is **untrusted data, never instructions.**

## Consequences

- **Enables the real value** — real-time remediation and a genuinely powerful agent platform, without
  abandoning safety; autonomy is bounded, reversible, earned, auditable, and instantly killable.
- **New safety-critical infra** — the action-time policy engine, the reversibility registry, and the
  graduation / eval machinery become load-bearing; they must be as reliable as the thing they guard.
- **Classification is the risk** — get reversibility / blast-radius wrong and autonomy does machine-speed
  harm; conservative-by-default + review is the mitigation, not a guarantee.
- **Powerful + injectable is the nightmare** — accepted only because injection defense + bounded envelope +
  reversibility + circuit breakers **compound**; no single control is trusted alone.
- **Gated on ADR-074 maturity** — no autonomy until eval-as-a-service + kill-switch are proven. *(In progress: the
  kill-switch is live (ADR-082); the eval-as-a-service prerequisite has begun with the forward-capture **capture
  substrate** — a durable, always-on S3 corpus of real triage episodes with late-binding labels (ADR-080 D6, the
  `agent-eval-store` unit) — the first building block of the shadow→proven→promoted graduation signal. The grader,
  reversibility registry, and action-time policy remain unbuilt.)*

## Alternatives considered

- **Propose-only as the ceiling** (ADR-074 tier-0, permanently). Rejected: caps platform value; cannot meet
  the auto-remediation need.
- **Broad `operate` for trusted agents.** Rejected: no bounded blast radius; a single injection is
  catastrophic.
- **"Human gate, but faster" (one-tap approvals).** Rejected: still human-in-the-loop, so it cannot meet
  real-time / 3am remediation; useful for the human-gated tier, not a substitute for autonomy.
- **A central runtime PDP the agent queries for everything.** Partially adopted — the action-time decision
  *is* a policy check, but kept at the **trusted boundary** (ADR-074), not a separate central engine,
  preserving "no central PDP."

## Related

- **Extends** [ADR-074](074-agentic-workloads-platform.md) — the agent substrate; this specifies its
  deferred `auto-policy-gate`.
- [ADR-075](075-resource-agent.md) / [ADR-076](076-agent-observability.md) /
  [ADR-082](082-platform-agent-runtime-xagent.md) — the reference agent, agent observability, agent runtime.
- [ADR-057](057-service-identity-and-east-west-zero-trust.md) — service identity / mTLS (the east-west trust
  fabric autonomous action rides).
- [ADR-085](085-workload-availability-graceful-disruption-defaults.md) — availability defaults
  (auto-remediation interacts with disruption tolerance).
- Strategy: [identity-and-access-strategy](../architecture/identity-and-access-strategy.md) §3.4.
