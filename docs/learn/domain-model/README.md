# Learn: the domain model

The shared vocabulary of the platform — **Team, Product, Service, Environment** (and **Customer**) — and
how they relate. Provisioning, access, delivery, and cost all derive from these nouns, so start here before
any other module.

**Audience:** everyone. For developers it's the model your code lives in; for platform engineers it's what
governance and automation hang off. No prior platform knowledge needed.

## Read in this order

1. **[Orientation](orientation.md)** — ownership is a tree, deployment is a grid. Walk a real team (`acme`)
   down the tree and across the grid.
2. **[Reference](reference.md)** — the terse lookup: the nouns as a schema, the relationships, the naming
   conventions, and the Team envelope.

## Then

- [Environment API](../environment-api/) — how a single Environment (one grid cell) becomes real
  infrastructure. The natural next module.
- Source of truth: [Platform Domain API](../../architecture/platform-domain-api.md) ·
  [ADR-067](../../adrs/067-idp-domain-model.md).
