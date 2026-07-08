# Learn: Compliance & regulated workloads

How the platform handles compliance — and an honest account of what's *built*, what's *inert*, and what's
*aspirational*. The short version: **compliance-aware by design, not compliance-certified.** Compliance here
is a *lens* over the security modules plus one *dial* (a declared `tier` per environment), not a subsystem.

**Audience:** platform engineers, and anyone asking "could this run a HIPAA or PCI workload?" **Before you
start:** this rides on the security modules — read at least [Policy & admission](../policy/orientation.md)
first; [Supply chain](../supply-chain/orientation.md), [Runtime security](../runtime-security/orientation.md),
[Identity](../identity/orientation.md), and [Foundations](../foundations/README.md) (the SCPs) all feed in.

## Read in this order

1. **[Orientation](orientation.md)** — *"compliance is a lens and a dial, not a subsystem."* The tier as a
   declared, envelope-constrained dimension; how the security modules *are* the controls; and a ruthless
   built-vs-inert-vs-aspirational account. Metaphors: a building rated for a hazard it's never withstood; a
   security system designed to print an audit trail it doesn't yet print.
2. **[Reference](reference.md)** — the dense lookup: the tier model (+ the enum drift), the envelope
   validation, what the tier actually toggles today, the controls-as-compliance table, the ADR-055 assurance
   gap, the status ledger, gotchas.

This is a **short module** — no deep dives; the mechanisms live in the security modules it is a lens over.

## Then

- The controls compliance rides on: [Policy](../policy/orientation.md) · [Supply chain](../supply-chain/orientation.md) ·
  [Runtime security](../runtime-security/orientation.md) · [Identity](../identity/orientation.md) ·
  [Foundations](../foundations/README.md). The static control map: `docs/compliance/scp-control-mapping.md`.
