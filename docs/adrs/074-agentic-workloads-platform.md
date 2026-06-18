# ADR-074: Agentic Workloads — a Governed Platform for Running AI Agents

**Status:** Proposed (2026-06-18)

## Context

We are about to run our first AI agent on the platform — a conversational assistant that helps developers self-serve
cloud resources by co-authoring the governed claim (ADR-073 Phase B, #554). But that agent is **the first of many**:
troubleshooting agents, observability agents, and others will follow — **some built in-house, some third-party.** If we
build the resource agent as a one-off, we will rebuild its governance, identity, evaluation, and safety machinery for
every subsequent agent, and each will be governed differently.

So the decision this ADR records is **not** "how to build one agent." It is: **treat agentic workloads as a
first-class, governed workload class, and build the substrate to run, govern, and secure many of them at scale —
safety paramount.**

The key enabling insight: **this is not a greenfield agent platform.** An agent is a workload with extra demands, and
the platform already does governed workloads well. The governance moat extends directly:

| Agent need | Existing platform capability it rides |
|---|---|
| Scoped, least-privilege identity | Crossplane-derived EKS Pod Identity (ADR-041/047) |
| Admission/policy governance | Kyverno enforce (ADR-014) + the governed-claim spine |
| Supply-chain trust (esp. third-party) | cosign keyless + SLSA provenance (ADR-042/050) |
| Isolation + zero-trust networking | namespace isolation + Cilium network policy / egress |
| "Propose, don't act" / human gate | the gated-PR + release-approver model (ADR-062/067/068) |
| Federated multi-cluster delivery | the per-cluster Crossplane control plane (ADR-048) |

This decision is grounded in (a) a deep technical-research pass on agent architecture, failure modes, and tooling, and
(b) **Singapore's IMDA Model AI Governance Framework for Agentic AI (MGF, Jan 2026)** and the companion **CSA "Securing
Agentic AI"** paper, which we adopt as the governance backbone. The failure record is sobering and shapes the design:
AI code generators ship insecure output at a substantial baseline rate, every published prompt-injection defense is
individually bypassable, MCP integrations have demonstrated real data-exfiltration exploits, and an autonomous coding
agent deleted a production database during an explicit freeze. Every one of these validates a **zero-infrastructure-
privilege, propose-only** design where the worst case is a rejected pull request.

## Decision

Agents are a **first-class, governed workload class.** The platform provides an **Agentic Workloads substrate** that
makes every agent — in-house or third-party — safe by construction:

1. Agents are **constrained, grounded, propose-only** assistants (LLM-guided slot-filling toward a fixed governed
   artifact), **never autonomous actors with infrastructure privilege.**
2. An **`Agent` is a first-class CRD** — a declarative, Kyverno-governed, catalog-projected, git-native spec that the
   substrate reconciles into a running workload, exactly as `XEnvironment` is reconciled today.
3. The substrate supplies the cross-cutting concerns once — **identity & authority, disposition (the gate), the LLM
   data boundary, risk-tiering, evaluation, lifecycle, cost, and observability** — and every agent inherits them.
4. The whole design is **cross-walked to the IMDA MGF**, and **safety invariants are not configurable.**

The resource agent (ADR-075) is **tier-0: the first reference tenant and deliberate low-stakes proving ground** — not
the killer app. It exercises every substrate primitive end-to-end at minimal risk; the high-value agents come once the
substrate is proven.

## The design

### Spectrum position & the hard boundary

A **hybrid LLM-guided slot-filling** agent toward a *fixed* schema (the slots **are** the target artifact's fields) —
**not** an open autonomous agent. It is RAG-grounded on the live catalog/policy so it proposes only **in-policy**
options, emits via **structured outputs / strict tool use** (constrained decoding → a structurally-valid artifact), holds
**zero infrastructure privilege**, and routes everything through **human-confirm + the existing policy gate.** Structural
validity ≠ policy validity, so **the gate remains load-bearing** — the agent can never replace it.

### `Agent` as a governed workload (CRD)

`Agent` joins `Team`/`Product`/`XEnvironment`/`AccessGrant` as a git-native kind: spec in git → **Kyverno-validated
against platform bounds** → **gated-PR reviewed** → **Backstage-catalog projected** → reconciled into a running workload
(mechanism — a Crossplane `XAgent` composite vs an operator-reconciled CRD — is an implementation choice; the composite
shape is favored for consistency with `XEnvironment`). Agents are **federated per-cluster like Crossplane** (ADR-048).

### Identity & authority

Three identities, kept **separate**: (1) the agent's own workload identity (least-privilege, often near-zero —
Pod Identity), (2) its **tool/model grant** (scoped by tier), (3) **on-behalf-of-user delegation.** The governing rule:
**effective authority = intersection(the agent's grant, the calling human's scope)** — enforced by **trusted code at the
boundary** (context assembly + the action + the gate), **never by the agent.** Delegation across chains is
**attenuating and non-escalating** (capability attenuation; each hop can only narrow). There is **one access model** —
agents are subjects in the **AccessGrant model (ADR-068), extended**; delegation is a grant; no parallel model. Every
agent has a **named, accountable human sponsor** plus an owning team.

### Disposition — the gate, generalized

**Propose-don't-act** with a **universal no-bypass invariant** (no agent ever gets a direct-action path around the gate).
"The gate" is **tiered disposition**, keyed to risk × reversibility (MGF-aligned, which prescribes human approval at
*significant/irreversible* checkpoints — explicitly *not* every checkpoint):

- **auto-policy-gate** — low-risk, reversible actions (deterministic checks, no human);
- **human gate** — significant/irreversible;
- **multi-human gate** — high-stakes/regulated.

This is what permits eventual *autonomous* agent-to-agent chains to run without a human per step, without abandoning
"propose, don't act."

### The LLM data boundary

The **context window is an authz boundary** — assembled strictly within the caller's team scope (reusing the
permission model), so cross-tenant context is structurally impossible. A **tier-keyed data-classification gate** governs
what data classes may enter context; **secrets never enter context** (invariant). Model API use is under
**zero-retention / no-training** terms. Egress is **per-cluster / per-compliance-tier**: in a regulated (PCI/HIPAA)
cluster an agent egresses only to a **compliant model endpoint** or **not at all** (Cilium egress control).

### Risk-tiering

Per MGF "bound risk upfront": an agent's controls scale with **autonomy × reversibility × data sensitivity × cluster
compliance tier.** The resource agent is the lowest tier. Tiers are governed configuration, not code.

### Evaluation as a substrate service

The **CI gate for agents.** Grade the **artifact, not the path**; gate releases on **pass^k consistency** (threshold by
tier); combine code + LLM-judge + human graders plus a static scan; run **continuous/regression** eval (drift) and
**online outcome signals** (e.g. proposal accepted vs abandoned). Eval-as-a-service (with lifecycle, below) is the
explicit **prerequisite for autonomous agents**, which lack a per-action human check.

### Lifecycle, versioning & the kill-switch

An agent's **version is composite**: `{image, prompt@v, model@v (PINNED — never floating), tool-set@v, eval-result}`.
A prompt/model/tool change is a new release that re-runs eval and promotes through the existing ladder (canary,
rollback). **Pinning the model** prevents silent behavioral drift. The one new primitive is a **kill-switch** — a
per-agent enablement flag plus a global breaker, enforced per-invocation (faster than a deploy), operable by the
sponsor + platform on-call, audited; a disabled/failed agent **falls back to the deterministic path.** Gradual rollout
(by team/scope) and incident response (sponsor paged; failing case → eval set) are required.

### Prompt & config as a governed artifact

An agent's behavior *is* configuration (system prompt + tool/MCP set + model + params). It gets **image-grade
supply-chain rigor**: baked into the **signed release**, changed only via **elevated review** (security-reviewer,
author ≠ approver — the prompt is partly a *control surface*), with the **tool/MCP allow-list governed** alongside it,
and **provenance separation at runtime** (the system prompt comes only from the signed source; conversation input is
untrusted data, never merged into system-prompt trust — the core prompt-injection defense).

### Cost / FinOps

The **model gateway** is the enforcement point — metering, per-tenant/agent budgets, rate limits, a circuit-breaker
(runaway guard, which also ties to the kill-switch). Agent inference cost is a new **cost source that folds into the
broader (greenfield) platform FinOps effort** — not a parallel system.

### Multi-agent & autonomous agent-to-agent (A2A)

Cascading failure is **prevented by construction**: propose-don't-act + no-bypass mean one agent's bad output can't
become another's unmediated input — it hits the gate first. **A2A is a governed tool** (it rides the same identity,
intersection/attenuation, allow-list, and gate; no separate channel). Conflicts on shared artifacts ride gitops;
tracing is **causality-aware.** Autonomous A2A is **designed-for** (tiered disposition + attenuating delegation +
chain budgets and depth bounds) but **built only behind a mature safety substrate** (eval-as-a-service + kill-switch).

### Configurability

An agent is a **declarative `Agent` spec.** Configuration is **two-level and bounded**: the platform sets bounds as
**policy-as-config** (the tier→controls mapping, the model and tool/MCP catalogs, eval thresholds, budgets, disposition
rules, data-classification rules); a sponsor configures their agent **within** those bounds. The bright line:
**mechanism is configurable; safety invariants are not** — propose-don't-act, the gate, intersection/attenuation,
no-bypass, and zero-privilege-by-default are never knobs.

### Build vs adopt

**Reuse** the platform (runtime, identity, delivery, policy, observability). **Adopt** commodity plumbing — the
**AI/model gateway**, **MCP**, Claude **structured outputs / tool use**, **guardrail libraries**, an **eval harness**,
and **OpenTelemetry GenAI** tracing. **Build** the governed integration that ties them to our substrate — **that is the
moat.** **Do not adopt a wholesale agent platform**: it would bring its own runtime/identity/governance that conflicts
with the governed-infra substrate that is our entire differentiator. Specific tool selections are a de-risking spike.

### User experience

A **channel-agnostic agent core** plus thin **channel adapters** — Backstage first; Slack/Discord later (with identity
mapping, channel risk-tier, and per-channel confirm rendering as the named hard parts). Agents are surfaced
**embedded at the point of need** with the deterministic form as a visible **peer and fallback**, and every proposal is
confirmed on the **concrete artifact** (review the diff, not prose). Scope is bounded and the AI is disclosed (MGF
end-user responsibility).

### Governance backbone (cross-walk)

We **anchor on the IMDA MGF + CSA**, use **OWASP Agentic/LLM Top 10 + MITRE ATLAS** as the threat/controls checklist,
and treat **NIST AI RMF / ISO 42001 / EU AI Act as deferred cross-walks** (design-for, don't certify pre-driver). The
substrate maps each control to an MGF pillar:

| MGF pillar | Controls here |
|---|---|
| Bound risk upfront | risk-tiering · agent identity + sponsor · data-classification gate · least-privilege grants |
| Human accountability | named sponsor · tiered disposition · the gated PR (author ≠ approver) |
| Technical controls (lifecycle) | least-privilege identity · sandbox/egress by tier · eval-as-a-service · kill-switch · pinned model · two-stream logging · supply-chain-governed prompt/tools |
| End-user responsibility | UX transparency · the artifact-confirm step |

## Tier-0: the first reference agent

The resource agent (**ADR-075**) is built on this substrate at the lowest tier — zero privilege, the existing access
model, the form as oracle and fallback — to prove the substrate end-to-end before any higher-value or autonomous agent.

## Phasing & sequencing

1. This ADR + the sibling ADR-075 (design of record).
2. **De-risking spikes** (structured-output conformance/policy-validity on the real claim schema; untrusted-context/IPI
   handling; component evaluation). Code is gated on these.
3. **Tier-0 resource agent** on the substrate (its own build plan).
4. A **decision gate** — is the substrate trustworthy, and is the next high-value agent worth building?
5. **Eval-as-a-service + kill-switch + monitoring** mature → **autonomous agents** unlocked.

**Prerequisite:** the unified access model (AccessGrant, ADR-068) is today a CRD shell with no enforcement and is
rebuild-gated; it is a prerequisite for the *broader* substrate (autonomous/cross-team agents), **not** for tier-0
(which rides the existing Keycloak model). The agent initiative is the concrete forcing function to prioritize it.

## Consequences

- A new, durable platform capability with its own pillar on the roadmap; agents become as governed as any workload.
- Strong positioning: a governed agent platform *on a real governed-infra substrate*, architected to a recognized
  agentic-AI governance framework — credible and compliance-aware.
- Real new surface to own: the model gateway, eval-as-a-service, the kill-switch, and the `Agent` CRD/controller.
- The safety posture is conservative by design (propose-only, zero privilege, gate-first); higher autonomy is earned
  behind explicit gates, not assumed.

## Alternatives considered

- **An open, tool-using autonomous agent** — rejected for tier-0: highest capability but highest eval burden,
  autonomy-regret exposure, injection surface, and tool-bloat failure modes; not how you prove a new capability safely.
- **A deterministic dynamic form only** — already exists; gives no elicitation help to the developer who doesn't know
  what they need (the agent's actual value).
- **Adopting a wholesale third-party agent platform** — rejected: it would not ride our governed-infra substrate (the
  moat) and would impose conflicting governance + lock-in. We adopt *components*, build the *integration*.
- **Building the plumbing from scratch** (gateway, eval harness, guardrails) — rejected: commodity, fast-moving, not
  the moat.

## Related

ADR-073 (self-service cloud resources — the agent's domain) · ADR-067/068 (domain model + access model) · ADR-048
(federated per-cluster Crossplane) · ADR-041/047 (Pod Identity) · ADR-014 (Kyverno) · ADR-042/050 (supply chain) ·
ADR-053/059 (identity/Keycloak) · ADR-062 (gated provisioning) · ADR-051/064 (Backstage). Sibling: **ADR-075** (the
resource agent, ADR-073 Phase B).
