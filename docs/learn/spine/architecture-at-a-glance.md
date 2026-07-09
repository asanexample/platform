# Architecture at a Glance

The whole platform on one page. Read it **bottom-up**: a cloud foundation, a Kubernetes cluster, a
declarative control plane, the tenancy model, the agents that run on and operate it, delivery, and the
edge — with **security/compliance** spanning the left and **observability** the right, and a **data &
resilience** strip underneath. Everything is git-driven and reconciled.

![The refplat architecture on one poster. Seven layers, bottom to top: foundation (AWS Organization, IaC, network, state), cluster (EKS, Cilium, Karpenter), the declarative control plane (Crossplane, Argo CD, Kyverno, Argo Rollouts), tenancy (Team → Product → Service → Environment), agentic (the XAgent runtime, autonomy ladder, triage copilot), delivery & DX (Backstage, supply chain, promotion), and the edge (Gateway API, ingress). Security, compliance, and identity span the left as a cross-cutting band; observability spans the right; a data & resilience strip (CloudNativePG, backups, reproducible-from-git) underpins the foundation. Key flows across the bottom: the GitOps loop, the paved road, the supply chain, agent provisioning, incident owner-routing, and the data plane.](../images/refplat-architecture-poster.svg)

[**Open the full-resolution poster ↗**](../images/refplat-architecture-poster.svg)

## Where to go deeper

The poster is the map; each layer has a module that goes deep:

- **Foundation** — [the account model & SCPs](../foundations/deep-dive-the-account-model.md) ·
  [networking](../foundations/deep-dive-networking.md) ·
  [infrastructure-as-code](../foundations/deep-dive-infrastructure-as-code.md) ·
  [nodes, scaling & access](../foundations/deep-dive-nodes-scaling-access.md)
- **Control plane & tenancy** — [the domain model](../domain-model/orientation.md) ·
  [the Environment API](../environment-api/orientation.md) ·
  [onboarding a Product](../products/orientation.md) ·
  [self-service resources](../self-service-resources/orientation.md)
- **Agentic** — [the agentic platform](../agentic/orientation.md)
- **Delivery & DX** — [delivery](../delivery/orientation.md) ·
  [developer experience](../developer-experience/orientation.md) ·
  [supply chain](../supply-chain/orientation.md)
- **Security & governance** — [the security model](the-security-model.md) ·
  [policy & admission](../policy/orientation.md) · [identity & access](../identity/orientation.md) ·
  [secrets & config](../secrets-config/orientation.md) · [runtime security](../runtime-security/orientation.md) ·
  [compliance](../compliance/orientation.md)
- **Observability & operations** — [observability](../observability/orientation.md) ·
  [cost & FinOps](../cost/orientation.md) · [operations](../operations/orientation.md)
