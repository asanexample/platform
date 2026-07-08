# Learn: The Agentic Platform

How the platform runs **AI agents** as first-class, *governed* workloads — bound so a compromised agent can't
cause harm, and made to earn trust rather than be given it. The platform's most distinctive, most
deliberately cautious area. A **sub-curriculum**: a whole-picture tour + focused deep dives.

**Audience:** platform engineers, and anyone wary of letting an LLM near production. **Before you start:**
[Environment API](../environment-api/orientation.md) (`XAgent` is its sibling), [Identity](../identity/orientation.md)
(an agent is a subject in the same model), [Observability](../observability/orientation.md), and
[Supply chain](../supply-chain/orientation.md) all help.

## Read in this order

1. **[Orientation](orientation.md)** — *"treat the agent like a powerful contractor you don't fully trust."*
   The one idea, and a tour: what an agent *is* (an `XAgent` claim) → how it's *bounded* → how it could *earn*
   more (the autonomy ladder) → the one real agent. With an honest "one agent, mostly early" status.
2. **[Reference](reference.md)** — the dense lookup: the ADR map, the `XAgent` claim + Composition, the
   GitOps control plane, the bounding machinery, the autonomy ladder, the triage copilot, the status ledger,
   gotchas.

## Go deep

- **[The XAgent runtime](deep-dive-the-xagent-runtime.md)** — the claim → slot Composition, the `XEnvironment`
  parallel, the GitOps control plane, Bedrock, and the lifecycle.
- **[Bounding the agent: identity & safety](deep-dive-bounding-the-agent.md)** — the scoped Pod Identity, the
  envelope, least privilege, the network lock, the data boundary, the kill-switch, and the admission gates.
- **[Autonomy & evaluation](deep-dive-autonomy-and-evaluation.md)** — the graduated, eval-gated autonomy
  ladder (designed), the eval loop, and the forward-capture substrate that *is* built.
- **[The triage copilot](deep-dive-the-triage-copilot.md)** — the one live agent, end to end, plus
  owner-routing (ADR-084).

## Then

- The agent's telemetry: [Observability → agent observability](../observability/deep-dive-agent-observability.md).
  Its identity model: [Identity & access](../identity/orientation.md). Its provisioning sibling:
  [Environment API](../environment-api/orientation.md). Author one: the `authoring-platform-agents` skill.
