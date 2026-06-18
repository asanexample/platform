# ADR-075: The Resource Agent — Conversational Self-Service for Cloud Resources (ADR-073 Phase B)

**Status:** Proposed (2026-06-18)

## Context

ADR-073 (self-service cloud resources) named a **Phase B** "agentic NL front door" and reserved a sibling ADR for it.
ADR-074 then established the **Agentic Workloads substrate** — the governed way to run *any* agent. This ADR specifies
the **first agent on that substrate: the resource agent**, and is deliberately scoped as **tier-0 — the lowest-risk
reference tenant and proving ground.**

Be clear-eyed about its value. The deterministic New Resource form already serves the developer who *knows what they
need* (it's a tiny 4-field domain). The resource agent's real value is the **uncertain** developer — "I need somewhere
to put uploaded files" — whom it helps via elicitation and cost/tradeoff explanation. Its **primary job, though, is to
prove the substrate end-to-end at minimal risk**, because its artifact (the claim) is uniquely *machine-checkable* (the
existing gate) and has a *deterministic oracle* (the form). It is not the killer app; it is the safe pipe-cleaner.

## Decision

Build the resource agent as a **channel-agnostic, envelope-grounded, slot-filling conversational assistant** that
elicits intent, **co-authors the governed claim by driving the existing `platform:add-service-resource` scaffolder
action**, confirms on the **concrete claim diff**, and opens the **existing gated PR** — holding **zero infrastructure
privilege.** It is **the first `Agent` CR** (ADR-074), at the lowest risk tier, with a **Backstage channel adapter only**
for the first release.

## Design

- **Conversation (slot-filling).** Elicit the few fields the claim needs (service · resourceName · engine · access;
  optional isolation/params), **grounded in the Team `envelope.resources`** so it only ever proposes **in-policy**
  options (no propose-then-reject). It explains cost/tradeoffs — the value-add over the form.
- **Emission (reuse, don't hand-write YAML).** The agent fills the inputs of the existing **`add-service-resource`**
  action (`backstage/packages/backend/src/scaffolder/addServiceResource.ts`); that deterministic code patches
  `services.<svc>.resources.<name>` and opens the PR. The agent produces the *same artifact the form does*.
- **The confirm step.** The agent shows the **exact claim diff** ("here's what I'll add to `dev.yaml`") for
  edit/approve/cancel — the human-disposition boundary made tangible (review the artifact, not prose).
- **Hand-off.** On approve → the action opens the **gated PR** (attributed to the developer) → the existing gitops gate
  validates + auto-merges dev / requires a release-approver for prod. **Restart-after-merge** is surfaced.
- **Access model.** Rides the **existing Keycloak model** — team membership via `authOidcModule.ts` /
  `permissionPolicy.ts` + the action's `verify-team-membership` + the gate. *Not* AccessGrant (ADR-068) yet; trivial to
  migrate when that matures.
- **Grounding freshness.** Grounds on the **live catalog metadata + envelope + schema** — a new engine (RDS, …) needs
  no agent change, only its catalog metadata + eval scenarios (ADR-073 extensibility, ADR-074 §catalog).
- **Evaluation.** Reuse-based: **code grader** = the gitops gate + Kyverno envelope; **oracle** = the form's
  deterministic output for the same captured intent; **pass^k** consistency gate; **outcome signals** in prod (PR
  merged-vs-abandoned, turns-to-completion, abandonment) as cheap online eval + conversation-quality measure. No
  LLM-judge needed at tier-0 (we have an oracle).
- **Lifecycle & safety.** Composite versioned release `{image, prompt@v, model@v pinned, tools@v}`; the **kill-switch**
  → **falls back to the form**; prompt + tool-set baked into the **signed release** with elevated review; a model
  **metering seam + runaway guard**; a **cost-appropriate model** (cheap — it's simple slot-filling).
- **Surface.** Embedded at the point of need (Service entity page + alongside the scaffolder form), form as visible
  peer/fallback; channel-agnostic core so Slack/Discord are later adapters, not rewrites.

## Success criteria (the proving-ground bar — NOT "beat the form")

- **Substrate proven** — every ADR-074 primitive exercised E2E (Agent CR, identity, gate, pass^k eval, kill-switch,
  AgentOps, data-boundary, cost guard).
- **Safe** — zero out-of-policy claims reach merge, zero data-boundary violations, the agent never *acts* (only
  proposes), pass^k ≥ the tier-0 threshold.
- **At-least-as-good-as-the-form for the uncertain user** — produces a correct, accepted, in-policy claim; headline
  metric = **PR merged vs abandoned.**

The initiative's north-star (deflection of platform-team requests, time-to-resolution) is measured across *future*
high-value agents, **not** judged on this one.

## Scope

**In (tier-0):** channel-agnostic core + Backstage adapter; envelope-grounded slot-filling; cost explanation; the
claim-diff confirm; reuse of `add-service-resource` → gated PR; the first `Agent` CR (a thin reconciler is acceptable);
the reuse-based eval; kill-switch + form fallback; metering seam + runaway guard; live-catalog grounding.

**Deferred:** Slack/Discord adapters; a unified multi-agent assistant surface; multi-resource conversations; richer RAG;
cross-session memory; AccessGrant-based authz; LLM-judge / semantic conversation-quality eval. (Tracked in ADR-074's
follow-ups.)

## Dependencies

Gated on the **de-risking spikes** (ADR-074): structured-output **conformance + policy-validity on the real claim
schema** (does it need an auto-repair/conftest loop?), and **untrusted-context/IPI** handling for slot pre-fill. Builds
on the substrate primitives defined in ADR-074.

## Consequences

- The substrate gets validated against an oracle-able, low-risk first case before any higher-stakes agent.
- The form remains and is the fallback; nothing is taken away from developers who prefer it.
- Modest standalone value is *expected and acceptable* — the deliverable is a proven substrate, not a beloved resource chatbot.

## Alternatives considered

- **Form only (no agent)** — leaves the uncertain developer unserved and, more importantly, never builds the substrate
  the high-value agents need.
- **A fuller assistant first** (multi-resource + RAG + rich cost modeling) — larger surface, higher eval burden, slower
  to a safe first proof; deferred to follow-ons.

## Related

**ADR-074** (the substrate — parent) · ADR-073 (self-service resources — the domain) · ADR-067/068 (domain + access
model) · ADR-062 (gated provisioning) · ADR-051/064 (Backstage). Tracking epic: #554.
