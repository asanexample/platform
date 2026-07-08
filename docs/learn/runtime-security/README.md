# Learn: Runtime Security

How the platform defends a workload *while it runs* — the assume-breach layer, after admission and signed
images have already gated the door. Three runtime moves: encrypt the wire (WireGuard), authenticate each
service (mTLS/SPIRE), and detect misbehavior (Falco).

**Audience:** platform engineers. Read [Policy & admission](../policy/orientation.md) and
[Supply chain](../supply-chain/orientation.md) first — those are the *gates* this complements —
and [Foundations → the cluster](../foundations/deep-dive-the-cluster.md) for Cilium, which does most
of the work here.

## Read in this order

1. **[Orientation](orientation.md)** — *"assume something got in — defend the running workload."* Where runtime
   security sits in defense-in-depth, the three moves (encrypt / authenticate / detect), and an honest
   live-vs-designed status. Metaphor: a secure building past the front door.
2. **[Reference](reference.md)** — the dense lookup: the defense-in-depth stack, Falco (mechanism + deferred
   routing), east-west WireGuard + mTLS, the status ledger, gotchas.

## Go deep

- **[Falco — runtime threat detection](deep-dive-falco.md)** — syscalls → modern eBPF → the per-node
  DaemonSet → rules, the Kyverno-vs-Falco complement, falcosidekick + the deferred routing, and the tuning
  burden (why detection ships before routing).
- **[East-west zero-trust](deep-dive-east-west-zero-trust.md)** — Cilium WireGuard transparent encryption
  (live both clusters) and the Cilium + embedded-SPIRE **mTLS** showcase (preprod, one pair): the mechanism,
  the gotchas, and the honest status.

## Then

- The admission gate this complements: [Policy & admission](../policy/orientation.md). The image trust:
  [Supply chain](../supply-chain/orientation.md). The CNI doing the work: [Foundations → the cluster](../foundations/deep-dive-the-cluster.md).
