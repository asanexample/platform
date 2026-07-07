# ADR-057: Service Identity & East-West Zero Trust (mTLS)

**Date:** 2026-06-04

**Status:** **Phase 1 (transparent encryption): Accepted — built + live on preprod + platform, 2026-07-07.**
Phase 2 (Cilium mTLS + SPIFFE workload identity) remains **Proposed** (strategy). Completes the *east-west*
(service-to-service) half of the
security model, alongside the existing north-south ingress ([ADR-017](017-gateway-api-over-ingress.md)) and the
Cilium CNI ([ADR-008](008-cilium-as-cross-cloud-cni.md)). Aligns in-cluster workload identity with the cloud
identity ([ADR-041](041-pod-identity-for-tenant-workloads.md)/[ADR-047](047-pod-identity-as-aws-identity-standard.md))
and human identity ([ADR-053](053-identity-and-cross-system-authorization-strategy.md)) planes. The mTLS posture
becomes part of the tier's **network** isolation column ([ADR-049](049-tenant-model-team-tenant-zone.md)).

> **Amendment (2026-07-06, #1193) — Phase 1 (transparent encryption) split out and built into the module.**
> Decision #1's *encryption* half is concretized and made buildable now; the *mTLS / SPIFFE* half (decisions
> #2–#4) stays Proposed and parked (regulated-tier only — no regulated tenant exists yet — and it still needs
> the open Cilium-mTLS-vs-SPIRE spike).
>
> - **Backend: WireGuard** (`encryption.type=wireguard`) — in-kernel on the AL2023 6.x nodes (kernel 6.12, no
>   key management) and simplest on the platform's **overlay datapath** (tunnel/VXLAN + cluster-pool IPAM),
>   which sidesteps the WireGuard caveats that live in native-ENI mode. Cilium stacks it under the VXLAN
>   tunnel and auto-adjusts MTU for the added overhead.
> - **Open question resolved: fleet-default, not tier-gated.** Encryption-in-transit is a blanket good and
>   decision #3 already puts it in the `standard` tier, so it is enabled cluster-wide rather than per-tier.
> - **Scope: pod-to-pod only** — `node_encryption` (host-to-host) stays off for Phase 1 (it also covers host +
>   health-check traffic and is a more invasive later step).
> - **Delivered here:** gated module support in the `cilium` module (`encryption_enabled` / `encryption_type`
>   / `node_encryption`, default off). **Enablement is a separate step:** flipping a unit's input triggers a
>   **rolling Cilium restart** on the CNI — highest blast radius — so it rolls out **preprod-first**, in a
>   maintenance window, from the main checkout, with a **perf-overhead measurement** before the platform
>   cluster follows. Status flips to Accepted once applied + verified.

## Implementation notes (as-built) — Phase 1, 2026-07-07

WireGuard transparent encryption is **live and verified on both clusters** (`cilium-dbg status` →
`Encryption: Wireguard [cilium_wg0 … Peers: N]`; every node carries a `network.cilium.io/wg-pub-key`
annotation + `spec.encryption.key` in its CiliumNode; cluster health returned to N/N reachable; a public
preprod route and an internal platform route both served **HTTP 200** through the encrypted mesh — no MTU
black-holing on the tunnel/VXLAN datapath). Module support: [#1193](https://github.com/asanexample/platform/pull/1193);
per-cluster enablement is the `cilium` unit input `encryption_enabled = true`.

**Gotcha (the real lesson): enabling encryption does *not* auto-activate it on running agents.** The helm
change sets `enable-wireguard=true` in the `cilium-config` ConfigMap, but Cilium reads that value **only at
agent startup** — the DaemonSet is not rolled by the config change. Symptom: only nodes whose agent
(re)started after the change bring `cilium_wg0` up; pre-existing agents log
`Mismatch: enable-wireguard actual=false expectedValue=true`. **Required step after the apply:
`kubectl rollout restart ds/cilium -n kube-system`** — then all agents re-read the config and establish the
mesh. Auto-triggering this roll on an encryption-config change is a sensible module follow-up.

**Correction to the amendment above:** the "maintenance window / from the main checkout" framing proved
unnecessary on these dev clusters — the rolling agent restart is a brief per-node blip (shared services and
tenant apps stayed healthy), and the apply ran cleanly from a worktree (the cilium unit's only
`null_resource` uses a `version` trigger, not a path, so it is not the worktree footgun other units carry).

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
