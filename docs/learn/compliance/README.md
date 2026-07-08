# Learn: Compliance & regulated workloads

The platform is **compliance-aware by design, not compliance-certified** — and this module is honest about
which controls are built, which are inert, and which are still aspirational. Compliance isn't a subsystem
here. It's a lens over the security modules plus one dial: a declared `tier` per environment.

This is for platform engineers, and for anyone asking "could this run a HIPAA or PCI workload?" It rides on
the security modules, so read at least [Policy & admission](../policy/orientation.md) first;
[Supply chain](../supply-chain/orientation.md), [Runtime security](../runtime-security/orientation.md),
[Identity](../identity/orientation.md), and [Foundations](../foundations/README.md) (the SCPs) all feed in.

## Read in this order

1. **[Orientation](orientation.md)** — the tier as a declared, envelope-constrained dimension; how the
   security modules *are* the controls; and a plain account of what's built versus inert versus aspirational.
   Two metaphors carry it: a building rated for a hazard it's never withstood, and a security system designed
   to print an audit trail it doesn't yet print.
2. **[Reference](reference.md)** — the dense lookup: the tier model and its enum drift, the envelope
   validation, what the tier actually toggles today, the controls-as-compliance table, the ADR-055 assurance
   gap, the status ledger, and the gotchas.

There are no deep dives — the mechanisms live in the security modules this module is a lens over.

## Then

- The controls compliance rides on: [Policy](../policy/orientation.md) · [Supply chain](../supply-chain/orientation.md) ·
  [Runtime security](../runtime-security/orientation.md) · [Identity](../identity/orientation.md) ·
  [Foundations](../foundations/README.md). The static control map: `docs/compliance/scp-control-mapping.md`.
