# East-West Zero Trust — Encryption + Mutual Authentication

How the platform secures **service-to-service** (east-west) traffic inside the cluster: transparently
encrypting it on the wire, and letting services **cryptographically prove who they are** to each other.
The decision record is [ADR-057](../adrs/057-service-identity-and-east-west-zero-trust.md); this is the
as-built "how it works, how to use it, how to verify."

North-south (ingress) is already TLS + hostname-scoped at the Gateway ([Gateway & Ingress](gateway-and-ingress.md)).
East-west was, until now, governed only by **Cilium NetworkPolicy** — strong *network* identity (label →
security-identity → IP), but not *cryptographic* workload identity, and not encrypted on the wire. This closes
both gaps.

## The mental model: two separate jobs

"Secure east-west" bundles two things that are easy to conflate but do different work:

| Layer | Question it answers | Mechanism |
|-------|---------------------|-----------|
| **1. Encryption** | Is the traffic *readable* on the wire? | Cilium **WireGuard** transparent encryption |
| **2. Mutual auth** | Can each service *prove who it is*? | Cilium **mutual authentication** + **SPIFFE** identities from an embedded **SPIRE** |

**Phase 1 encrypts the pipe. Phase 2 proves who's on each end.** They compose — mutual auth authenticates
the workload; the data still rides on the WireGuard-encrypted wire. Neither replaces NetworkPolicy; they
layer *under* it.

## Layer 1 — Transparent encryption (WireGuard)

**What:** every pod-to-pod packet leaving a node is encrypted with WireGuard (in-kernel on the AL2023 nodes),
transparently — **no application changes**. On this platform's overlay datapath (VXLAN + cluster-pool IPAM),
Cilium stacks WireGuard under the VXLAN tunnel and auto-adjusts MTU.

**Status:** live and **fleet-default on both clusters** (preprod + platform).

**Enable** (per cluster, in the `cilium` live unit):

```hcl
encryption_enabled = true   # encryption_type defaults to "wireguard"
```

Enabling is a **rolling Cilium restart** — Cilium reads `enable-wireguard` only at agent startup, so after the
apply you must roll the DaemonSet:

```bash
kubectl rollout restart ds/cilium -n kube-system   # deployer context for the write
```

**Verify:**

```bash
kubectl -n kube-system exec <cilium-pod> -c cilium-agent -- cilium-dbg status | grep Encryption
#   Encryption:  Wireguard  [cilium_wg0 (Pubkey: …, Port: 51871, Peers: N)]
kubectl get ciliumnodes -o custom-columns=NODE:.metadata.name,WG:.metadata.annotations.network\.cilium\.io/wg-pub-key
#   every node carries a WireGuard pubkey + spec.encryption.key
```

`node_encryption` (host-to-host, not just pod-to-pod) is off by default — a later, more invasive step.

## Layer 2 — Mutual authentication (SPIFFE / SPIRE)

**What:** Cilium **mutual authentication** gives each workload a **SPIFFE SVID** (a short-lived, attestable
identity document) issued by an **embedded SPIRE** (server StatefulSet + per-node agents, in the `cilium-spire`
namespace). When a `CiliumNetworkPolicy` marks an ingress rule `authentication.mode: required`, Cilium performs
a mutual-auth handshake — the two workloads cryptographically prove their identities — before the connection is
allowed. This is *authorization on attested identity*, not on network position.

**Why embedded SPIRE (not standalone):** Cilium's bundled SPIRE attests workloads via the Kubernetes PSAT node
attestor and issues SVIDs cleanly on this stack. A standalone SPIRE is only worth it if identities are needed
*beyond* Cilium (app-level mTLS, cross-cluster federation) — not the case today.

**Status:** live on **preprod** as a showcase (see the demo below). Fleet-wide, tier-gated enforcement is a
follow-up.

**Enable** (in the `cilium` live unit):

```hcl
mutual_auth_enabled = true   # installs the embedded SPIRE; spire_persistence defaults true
```

Two gotchas baked into the module:

- The chart's top-level `authentication.enabled` **must** be true (the module sets it when `mutual_auth_enabled`),
  or auth-required policies **deny** rather than bypass.
- The SPIRE server persists its datastore to a **PVC**, which needs an **encrypted** StorageClass where an SCP
  enforces EBS encryption. `spire_storage_class` defaults to the cluster's default class (the encrypted **gp3**
  we set on preprod). Set `spire_persistence = false` only for a throwaway (in-memory, ephemeral) setup.

Enabling is a **rolling Cilium restart**, same as encryption.

**Author an auth-required policy** — the *callee* declares who may call it, authenticated. Same-namespace
example (`checkout` accepts only `storefront`, both inside `alpha-shop-dev` — the real
`k8s/base/checkout/cnp-ingress-from-storefront.yaml` in the alpha-shop repo):

```yaml
apiVersion: cilium.io/v2
kind: CiliumNetworkPolicy
metadata:
  name: allow-checkout-ingress-from-storefront
spec:
  endpointSelector:
    matchLabels:
      app: checkout
  ingress:
    - fromEndpoints:
        - matchLabels:
            app: storefront        # same namespace — no namespace selector needed
      authentication:
        mode: required          # ← the mutual-auth requirement
      toPorts:
        - ports: [{ port: "8080", protocol: TCP }]
```

Tenants can author this in their own `k8s/` overlay — the delivery AppProject permits tenant
`(Cilium)NetworkPolicy` (namespaced + additive; a tenant can only open *its own* ingress, never override the
platform default-deny or IMDS `egressDeny`).

**Verify** the path is genuinely SPIRE-authenticated (not just a network allow):

```bash
kubectl -n kube-system exec <cilium-pod> -c cilium-agent -- cilium-dbg bpf auth list
#   SRC IDENTITY   DST IDENTITY   AUTH TYPE   EXPIRATION
#   <checkout-id>  <storefront-id> spire      <ts>       ← AUTH TYPE=spire = real mutual auth
```

## The demo — every hop in alpha-shop, plus a real cross-team call

The showcase is **real multi-service traffic**, not a synthetic one. Two live pairs, not one:

**1. Every intra-shop hop** (all inside `alpha-shop-dev`): `storefront → catalog`, `storefront → cart`,
`storefront → orders`, `storefront → checkout`, `storefront → accounts`, and `orders → payment` all carry
`authentication.mode: required` ingress CNPs like the one above — six authenticated pairs in one namespace.
Visiting the storefront and placing an order exercises all of them in one request chain.

**2. A genuinely cross-team call**: `orders` (team **alpha**, `alpha-shop-dev`) calls `intake` (team
**bravo**, `bravo-dispatch-dev`) to kick off a real shipment on checkout (ADR-101). Unlike the pairs above,
this one crosses a real team boundary, authorized by a `ServiceGrant` bravo authored for alpha
(`gitops/grants/bravo/allow-alpha-shop-orders-to-dispatch-intake.yaml`) with
`capability.network.authentication.mode: required` — the Crossplane `ServiceGrant` Composition renders both
CNP halves (egress in alpha's namespace, ingress in bravo's) from that one grant, nobody hand-authors either
side:

```text
https://shop-alpha-dev.preprod.aws.refplat.org — sign up, add a bike, check out
# → the order confirmation shows a Bravo Dispatch tracking id once intake accepts the shipment,
#   proof orders → intake actually happened (checkout requires a signed-in account, so this is a
#   real browser flow, not a bare curl)
```

Both pairs share the same verification and the same failure mode:

- **Authorized + authenticated:** `cilium-dbg bpf auth list` shows `AUTH TYPE=spire` for every pair above.
- **Impostor denied:** a workload in any other namespace hitting `checkout` or `intake` is
  `Policy denied DROPPED` (`hubble observe --namespace alpha-shop-dev` / `--namespace bravo-dispatch-dev`).

That "same-authenticated-identity allowed, everything else denied" is the zero-trust story — on six live
pairs in one product, plus a real cross-team one, not a single showcase pair.

### The cross-namespace networking rule (important)

Environment namespaces are **default-deny both directions** (the Crossplane Composition stamps
default-deny-ingress + an egress policy that only permits DNS + world). A k8s `ipBlock` allow does **not** cover
in-cluster pod identities in Cilium — so a **cross-namespace** service-to-service call needs **both**:

- an **egress allow on the caller** (`orders` in `alpha-shop-dev` → `bravo-dispatch-dev`), and
- an **ingress allow on the callee** (`intake` in `bravo-dispatch-dev` ← `alpha-shop-dev`).

(The `ServiceGrant` Composition renders exactly these two — that's the whole point of the API: neither team
hand-authors the other's half.) The mutual-auth requirement replaces the *ingress* half (a plain allow would
bypass auth, since Cilium unions allows). Miss the egress half and the symptom is misleading — Hubble shows
the SYN reaching the callee's ingress as `Policy denied DROPPED`, so it *looks* like an ingress problem.

**This rule doesn't apply within a single namespace** — `storefront → checkout` (both in `alpha-shop-dev`)
needs only the one ingress CNP shown above; there's no second, cross-namespace egress half to forget.

## Current state & what's next

| | State |
|---|---|
| **Phase 1 — WireGuard encryption** | Live, fleet-default, **both clusters** |
| **Phase 2 — mutual auth + SPIFFE/SPIRE** | Live, **preprod**: 6 intra-`alpha-shop` pairs + the cross-team `orders → bravo-dispatch intake` pair (ADR-101) |
| **Follow-up** | Fleet-wide, **tier-gated** enforcement — generating `authentication.mode: required` policies from the Crossplane Composition per compliance tier (which already has `$tier` in scope) when a regulated tenant exists |

## References

- [ADR-057](../adrs/057-service-identity-and-east-west-zero-trust.md) — the decision + as-built notes
- `infra/modules/cilium` — module support (`encryption_enabled`, `mutual_auth_enabled`, `spire_install`,
  `spire_persistence`, `spire_storage_class`); see its README
- [Platform capability coverage](platform-capability-coverage.md) · [Security model (learn)](../learn/spine/the-security-model.md)
- [Gateway & Ingress](gateway-and-ingress.md) — the north-south companion
