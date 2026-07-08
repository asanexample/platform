# Learn: Identity & Access

Who — and *what* — is allowed to do things on this platform, and how that's controlled from one git source of
truth instead of a dozen consoles. The human and machine side of "least privilege, nothing standing."

Written for platform engineers who operate access; developers get the short version at the end of the
orientation. It covers the biggest pieces in one module — workload identity, temporary power, and the
governance registry may split out later. Already fluent? Go straight to the [Reference](reference.md).

Read the [domain model](../domain-model/orientation.md) (Team / Product) first, and ideally
[the security model](../spine/the-security-model.md).

## Read in this order

1. **[Orientation](orientation.md)** — the teaching path. The one idea (decide once in git, derive everywhere,
   trust nothing permanently), the two subjects (humans via Keycloak, workloads via Pod Identity), the roster
   and role catalog, and temporary power — dangerous roles you borrow, not hold. Real `Person`,
   `WorkforceRole`, and Pod Identity examples.
2. **[Reference](reference.md)** — look-up: the three planes, the role axes, projection targets, the
   temporary-power mechanism, workload identity, and the gotchas (declared ≠ effected).

## To go deeper on the real system

- The security framing: [The Security Model](../spine/the-security-model.md).
- Architecture (north star): [Identity & Access Strategy](../../architecture/identity-and-access-strategy.md).
- Why it's shaped this way: [ADR-053](../../adrs/053-identity-and-cross-system-authorization-strategy.md)
  (strategy), [ADR-059](../../adrs/059-identity-topology-pluggable-idp-seam.md) (Keycloak seam),
  [ADR-088](../../adrs/088-temporary-power-activation.md) (temporary power),
  [ADR-041](../../adrs/041-pod-identity-for-tenant-workloads.md) (Pod Identity),
  [ADR-089](../../adrs/089-governance-registry-topology.md) (the registry).
