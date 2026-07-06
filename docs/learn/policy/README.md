# Learn: Policy & Admission

How the platform enforces its rules — automatically, on every resource, at the moment it enters the cluster.
The guardrail engine ([Kyverno](https://kyverno.io/docs/)) behind "safe self-service": it *rejects* the
non-compliant, *injects* the safe defaults, and *generates* the companions — all at admission, all as code.

**Audience:** platform engineers who author or operate policy. Developers get an outsized payoff from the
**2-minute view** at the end of the orientation (what admission requires, and what it auto-injects for you).
Fluent in Kyverno? Skip to the [Reference](reference.md).

**Before you start:** know that Kubernetes stores YAML resources and a *namespace* is an isolated slice of a
cluster; the [domain model](../domain-model/orientation.md) helps (Team / Product / Environment).

## Read in this order

1. **[Orientation](orientation.md)** — the teaching journey. The one idea (a programmable checkpoint at the
   cluster door), the **three verbs** (validate · mutate · generate) taught on a *real* admission rejection,
   baseline-vs-per-product rules, and the Audit-first → Enforce rollout.
2. **[Reference](reference.md)** — look-up: the catalog shape, the enforce mechanics, the gotchas that bite
   (the deprecated `failureAction` field, the aggregated webhook, `Rollout` match), and a glossary.

## Then, to go deeper on the real system

- Admission in the whole flow: [The Life of a Deployment](../spine/life-of-a-deployment.md); as a security
  wall: [The Security Model](../spine/the-security-model.md).
- Architecture (as-built, per-cluster): [the Kyverno policy catalog](../../architecture/kyverno-policy-catalog.md).
- Author policies (producer side): the `kyverno-policy-authoring` skill. Write compliant workloads (consumer
  side): the `authoring-k8s-workloads` skill + [`compliant-deployment.yaml`](../../examples/compliant-deployment.yaml).
- Why it's shaped this way: [ADR-014](../../adrs/014-kyverno-as-policy-engine.md) (Kyverno as policy engine),
  [ADR-046](../../adrs/046-back-stack-for-developer-self-service.md) (the ownership split),
  [ADR-085](../../adrs/085-workload-availability-graceful-disruption-defaults.md) (the generated PDB).
