# Learn: Identity & Access

Who — and *what* — is allowed to do things on this platform, and how that's controlled from *one* git source
of truth instead of a dozen consoles. The human and machine side of "least privilege, nothing standing."

**Audience:** platform engineers who operate access; developers get the **2-minute view** at the end of the
orientation. This is a **sub-curriculum** — the biggest pieces in one module; deeper cuts (workload identity,
temporary power, the governance registry) may split out later. Fluent already? The [Reference](reference.md).

**Before you start:** the [domain model](../domain-model/orientation.md) (Team / Product) and ideally
[the security model](../spine/the-security-model.md).

## Read in this order

1. **[Orientation](orientation.md)** — the teaching journey. The one idea (*decide once in git, derive
   everywhere, trust nothing permanently*), the two subjects (humans via Keycloak, workloads via Pod
   Identity), the roster + role catalog, and — the best part — **temporary power** (dangerous roles you
   *borrow*, not hold). Real `Person`, `WorkforceRole`, and Pod Identity examples.
2. **[Reference](reference.md)** — look-up: the three planes, the role axes, projection targets, the
   temporary-power mechanism, workload identity, and the gotchas (declared ≠ effected).

## Then, to go deeper on the real system

- The security framing: [The Security Model](../spine/the-security-model.md).
- Architecture (north star): [Identity & Access Strategy](../../architecture/identity-and-access-strategy.md).
- Why it's shaped this way: [ADR-053](../../adrs/053-identity-and-cross-system-authorization-strategy.md)
  (strategy), [ADR-059](../../adrs/059-identity-topology-pluggable-idp-seam.md) (Keycloak seam),
  [ADR-088](../../adrs/088-temporary-power-activation.md) (temporary power),
  [ADR-041](../../adrs/041-pod-identity-for-tenant-workloads.md) (Pod Identity),
  [ADR-089](../../adrs/089-governance-registry-topology.md) (the registry).
