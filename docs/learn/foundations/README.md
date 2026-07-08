# Learn: Foundations

The ground the platform stands on — the AWS estate, how it's all defined as code, the network, the private
cluster, the compute, and the two guarded doors. Everything else (the Environment API, Delivery, Policy,
Identity) runs on top of this.

**Audience:** platform engineers who want a firm mental model of what's underneath. A developer never touches
most of it. Start with the [domain model](../domain-model/orientation.md), and ideally
[How the Platform Fits](../spine/how-the-platform-fits.md) — this is the bottom of that map. It helps to know
roughly what an AWS account, a VPC, and a Kubernetes cluster are.

## Read in this order

1. **[Orientation](orientation.md)** — a tour of the foundation. One idea (nested boundaries, private by
   default, all declared as code) and a metaphor-threaded walk from the outside in: the Organization and
   accounts, everything-as-code, the network, the private cluster, the compute, the two doors. Start here.
2. **[Reference](reference.md)** — the dense lookup: pinned versions, the accounts + SCPs + IAM table, the
   IaC cascade, networking, the cluster, compute, ingress/access, and the foundational gotchas.

## Go deep (one layer at a time)

- **[The account model & SCPs](deep-dive-the-account-model.md)** — the Organization, the five accounts, why
  an account is the *hard* isolation boundary, the eight org-wide guardrails, and the deploy/operate/state/
  break-glass IAM role model.
- **[Infrastructure as code](deep-dive-infrastructure-as-code.md)** — OpenTofu vs Terragrunt, the layered
  config cascade and `_base.hcl`, the account-match safety rails, remote state, and SOPS-in-git.
- **[Networking](deep-dive-networking.md)** — VPC topologies, the CIDR strategy, the Transit Gateway
  hub-and-spoke, and the cross-VPC DNS problem.
- **[The cluster & Cilium](deep-dive-the-cluster.md)** — the private-only EKS API, the BYOCNI four-layer
  build, Cilium's eBPF datapath (and why it replaces kube-proxy), and the ingress-identity gotcha.
- **[Nodes, scaling & access](deep-dive-nodes-scaling-access.md)** — the system node group vs Karpenter, the
  descheduler, and how humans reach a private cluster (Tailscale + why userspace mode).

## Then

- Where this sits in the whole: [How the Platform Fits](../spine/how-the-platform-fits.md) ·
  [The Security Model](../spine/the-security-model.md) (the foundation is its outer walls).
