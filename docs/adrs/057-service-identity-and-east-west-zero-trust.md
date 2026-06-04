# ADR-057: Service Identity & East-West Zero Trust (mTLS)

**Date:** 2026-06-04

**Status:** Proposed — **strategy/direction.** Completes the *east-west* (service-to-service) half of the
security model, alongside the existing north-south ingress ([ADR-017](017-gateway-api-over-ingress.md)) and the
Cilium CNI ([ADR-008](008-cilium-as-cross-cloud-cni.md)). Aligns in-cluster workload identity with the cloud
identity ([ADR-041](041-pod-identity-for-tenant-workloads.md)/[ADR-047](047-pod-identity-as-aws-identity-standard.md))
and human identity ([ADR-053](053-identity-and-cross-system-authorization-strategy.md)) planes. The mTLS posture
becomes part of the tier's **network** isolation column ([ADR-049](049-tenant-model-team-tenant-zone.md)).

## Context

North-south (ingress) is Gateway API + TLS. East-west is governed by Cilium **L3/L4 NetworkPolicy +
CiliumNetworkPolicy** — identity-aware at the *network* layer, and genuinely strong. But that is **network
identity, not cryptographic workload identity**: there is no mutual TLS between tenant services and no portable,
verifiable workload-identity document. Regulated / zero-trust postures expect **mTLS with attestable service
identity** between services, plus encryption-in-transit on the wire *inside* the cluster — neither of which the
platform offers today.

## Decision

1. **Cilium-native encryption + mTLS as the default — no separate sidecar mesh.** Cilium **transparent
   encryption** (WireGuard) provides the blanket in-cluster wire encryption; **Cilium mTLS** provides
   authenticated service identity where required. This avoids bolting on Istio/Linkerd for a capability Cilium
   largely covers, given the platform is already all-in on Cilium.
2. **SPIFFE IDs as the workload-identity primitive** for cryptographic service identity (regulated tiers). This
   gives the platform **one coherent identity narrative across all three planes** — SPIFFE for workload↔workload,
   Pod Identity for workload→cloud, Keycloak/OIDC for human→system.
3. **mTLS posture is a tier property** (the network column of the isolation spectrum, ADR-049): `standard` =
   NetworkPolicy isolation + transparent encryption; `regulated` = **enforced mTLS with workload-identity authz**
   between services. No new top-level tier dimension — it refines the existing network posture.
4. **No full service mesh unless forced.** The trigger that would justify a mesh is **L7 east-west traffic
   management** (e.g. service-to-service canary, [ADR-056](056-progressive-delivery-and-safe-rollback.md)).
   Until then Cilium covers L3/L4 + mTLS without the operational weight of a mesh.

## Alternatives considered

- **A full service mesh (Istio / Linkerd) as the default.** Large operational surface (sidecars/ambient,
  control plane) for a capability Cilium mostly provides. Rejected as default; revisited only if L7 east-west
  features are required.
- **Application-level mTLS** (each app terminates its own). Not uniform, per-app toil, no shared identity root.
  Rejected.
- **Network policy only** (status quo). Sufficient for `standard`, insufficient for zero-trust / regulated —
  network identity is not cryptographic workload identity. Rejected for regulated tiers.

## Consequences

- Completes the **zero-trust east-west** story for regulated workloads and unifies workload identity (SPIFFE)
  with the AWS and human identity planes already decided.
- Refines the tier's network posture rather than adding a dimension — the model absorbs it cleanly.
- **Risk: Cilium mTLS maturity** — evaluate against the regulated requirement before committing regulated
  workloads; a SPIRE deployment is the fallback identity source.
- Cost: the performance overhead of transparent encryption (measure before enabling fleet-wide).
- **Open:** Cilium mTLS vs an explicit SPIRE deployment; whether encryption is fleet-default or tier-gated.
