# Learn: The Agentic Platform

How the platform runs AI agents as governed workloads — bound so a compromised agent can't cause harm, and
made to earn trust rather than be given it. This is the platform's most distinctive and most deliberately
cautious area. What follows is a whole-picture tour plus focused deep dives.

**Audience:** platform engineers, and anyone wary of letting an LLM near production. It helps to have read
[Environment API](../environment-api/orientation.md) (`XAgent` is its sibling), [Identity](../identity/orientation.md)
(an agent is a subject in the same model), [Observability](../observability/orientation.md), and
[Supply chain](../supply-chain/orientation.md), but none is required.

## Read in this order

1. **[Orientation](orientation.md)** — *"treat the agent like a powerful contractor you don't fully trust."*
   The one idea, and a tour: what an agent is (an `XAgent` claim), how it's bounded, and how it could earn
   more (the autonomy ladder), ending on the one real agent. Includes an honest "one agent, mostly early"
   status.
2. **[Reference](reference.md)** — the dense lookup: the `XAgent` claim and Composition, the
   GitOps control plane, the bounding machinery, the autonomy ladder, the triage copilot, the status ledger,
   and gotchas.

## Go deep

- **[The XAgent runtime](deep-dive-the-xagent-runtime.md)** — the claim → slot Composition, the `XEnvironment`
  parallel, the GitOps control plane, Bedrock, and the lifecycle.
- **[Bounding the agent: identity & safety](deep-dive-bounding-the-agent.md)** — the scoped Pod Identity, the
  envelope, least privilege, the network lock, the data boundary, the kill-switch, and the admission gates.
- **[Autonomy & evaluation](deep-dive-autonomy-and-evaluation.md)** — the graduated, eval-gated autonomy
  ladder (designed), the eval loop, and the forward-capture substrate that *is* built.
- **[The triage copilot](deep-dive-the-triage-copilot.md)** — the one live agent, end to end, plus
  owner-routing.

## Then

- The agent's telemetry: [Observability → agent observability](../observability/deep-dive-agent-observability.md).
  Its identity model: [Identity & access](../identity/orientation.md). Its provisioning sibling:
  [Environment API](../environment-api/orientation.md). To author one, use the `authoring-platform-agents` skill.
