# ADR-008: Cilium as Cross-Cloud CNI

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform runs Kubernetes on **AWS (EKS) today**, with **Azure (AKS) and GCP (GKE) planned**
(deferred until AWS is stable — see [ADR-001](001-multi-cloud-terragrunt-structure.md)). Each cloud
offers a default CNI — AWS VPC CNI, Azure CNI, GKE's default — but these are tightly coupled to their
cloud networking models and offer inconsistent feature sets for network policy, observability, and
service mesh. Picking one CNI that works across all of them keeps the networking model uniform as
clouds are added.

Operating different CNIs per cloud creates several problems:

1. **Inconsistent network policy semantics.** Kubernetes NetworkPolicy behavior varies across CNI
   implementations. A policy that works on one cloud may silently behave differently on another.

2. **No unified observability.** Each cloud CNI has its own metrics, logging, and flow visibility
   tools. There's no single pane of glass for network flows across clusters.

3. **Feature fragmentation.** Advanced features like L7 network policy, FQDN-based egress rules,
   transparent encryption, and Gateway API support are available in some cloud CNIs but not others.

4. **Operational overhead.** Engineers must learn and troubleshoot different networking stacks per
   cloud, increasing cognitive load and incident response time.

### Alternatives Considered

**1. Cloud-native CNI per provider.** Use AWS VPC CNI on EKS, Azure CNI on AKS, GKE default on
GKE. Simplest to set up — each cloud's managed Kubernetes service "just works" with its native
CNI. However, this accepts all the fragmentation problems above and makes cross-cloud network
policy and observability impossible to standardize.

**2. Calico across all clouds.** Calico is widely used and supports multi-cloud deployments. It
provides consistent network policy and can run in overlay or native modes. However, Calico lacks
Cilium's eBPF-based dataplane performance, Hubble observability (per-pod flow logs, service maps,
L7 metrics), and native Gateway API support. Calico's eBPF mode is less mature.

**3. Cilium across all clouds (chosen).** Cilium uses eBPF for high-performance networking and
provides a unified feature set: CiliumNetworkPolicy (L3-L7), Hubble observability, kube-proxy
replacement, Gateway API, and ClusterMesh for cross-cluster communication. It supports
cloud-specific IPAM modes (ENI on AWS, cluster-pool on Azure) while maintaining a consistent
control plane and policy model.

## Decision

Use Cilium as the CNI on all Kubernetes clusters via a "bring your own CNI" (BYOCNI) approach.
A single shared module (`infra/modules/cilium/`) accepts a `cloud_provider` variable that selects
the appropriate networking mode for each cloud.

### Cloud-Specific Modes

| Setting | AWS (EKS) | Azure (AKS) | GCP (GKE) |
|---------|-----------|-------------|-----------|
| IPAM mode | Cluster pool (overlay) | Cluster pool | Kubernetes |
| Routing | VXLAN tunnel | VXLAN tunnel | Native |
| Masquerade | BPF (overlay default) | Default | `ens+` for native |
| kube-proxy replacement | Required (`true`) | Configurable | Configurable |
| Hubble | Enabled (TLS via `helm` method) | Enabled | Enabled |
| Gateway API | Enabled | Enabled | Enabled |

Only **AWS (EKS)** is deployed today; the Azure/GCP columns are the module's `cloud_provider` branches
(present and validated in `infra/modules/cilium/`), ready for when those clouds land.

### AWS Overlay Datapath (cluster-pool IPAM + VXLAN)

On EKS today, Cilium runs an **overlay** datapath: `ipam_mode = "cluster-pool"` with
`routing_mode = "tunnel"` / `tunnel_protocol = "vxlan"` (the module defaults). Pods draw from a
dedicated, non-routable `pod_cidr` (platform `10.240.0.0/16`, a per-cluster /16 from the reserved
`10.240.0.0/14` pod supernet — ClusterMesh-ready), **not** from the VPC node subnet, and pod-to-pod
traffic is VXLAN-encapsulated between nodes. Egress masquerade uses Cilium's BPF masquerade
(`egress_masquerade_interfaces` empty) rather than an interface glob.

> **AWS ENI/native mode is an opt-in override, not the default.** Setting `ipam_mode = "eni"` (with
> `routing_mode = "native"` and `egress_masquerade_interfaces = "ens+"` for Amazon Linux 2023's
> predictable interface names) switches the cluster to VPC-native ENI routing — pods then get VPC
> subnet IPs via ENI secondary IPs. The platform does not run this mode today; choose it only when
> VPC-native pod IPs are a hard requirement, mindful of subnet-IP exhaustion.

### Kube-Proxy Replacement on EKS

On EKS with BYOCNI (`bootstrap_self_managed_addons = false`), no `kube-proxy` DaemonSet is
deployed. Cilium must take over all kube-proxy duties by setting `kubeProxyReplacement = true` in
the AWS cloud values. Without this, NodePort and LoadBalancer services have no implementation and
connections to service ports are refused.

### Gateway API and the `ingress` Identity

Cilium's Gateway API implementation uses an external Envoy DaemonSet running with `hostNetwork`.
When Envoy makes upstream connections to backend pods, it does **not** use the node's primary IP
or the `host` Cilium identity. Instead, Cilium assigns the upstream source the reserved `ingress`
identity (identity 8), configured via the `cilium.bpf_metadata` listener filter's
`ipv4_source_address` field. (This identity behaviour is datapath-independent — it holds under both
the overlay and ENI modes.)

Any CiliumNetworkPolicy protecting tenant namespaces that receive Gateway API traffic must include
`ingress` in their `fromEntities` list. Standard Kubernetes NetworkPolicy `ipBlock` CIDR rules do
not work as a substitute — Cilium's identity-based matching takes precedence when the source IP
has a known identity in the BPF ipcache.

### TLS Secret Sync for Gateway API

Gateway API TLS secrets referenced by Gateway listeners must exist in the `cilium-secrets`
namespace with the naming convention `<source-namespace>-<secret-name>`. For example, a Gateway
in the `default` namespace referencing secret `preprod-gateway-tls` requires a copy at
`cilium-secrets/default-preprod-gateway-tls`. This sync is not automatic — it must be handled
by the platform (e.g., via the gateway-config module or a secret copy mechanism).

### Hubble TLS

On all clouds, Hubble TLS certificates use the `helm` method — certificates generated by the Helm
chart itself — rather than `certmanager`. This avoids a chicken-and-egg problem: cert-manager
requires a running CNI to schedule its pods, but Cilium must be deployed before any pods
(including cert-manager) can run.

### BYOCNI Deployment Ordering

BYOCNI creates a strict dependency chain:

```text
Cluster (no CNI) → Cilium (installs CNI) → Node Groups (join cluster) → Add-ons (pods schedule)
```

On EKS, this is enforced by setting `bootstrap_self_managed_addons = false` on the cluster
resource and using Terragrunt dependencies to order the deployment units. See ADR-009 for details
on the component separation.

### Helm Chart Version

Cilium chart version is centrally pinned in `infra/live/aws/_versions.hcl` (currently 1.19.4).
The module accepts a `helm_chart_version` variable that defaults to 1.19.4 as a fallback.

## Consequences

**Positive:**

- Consistent network policy semantics across all clouds — CiliumNetworkPolicy CRDs work
  identically regardless of underlying cloud networking
- Unified observability via Hubble: per-pod flow logs, service maps, L7 metrics, DNS visibility
- kube-proxy replacement eliminates iptables overhead on large clusters
- Gateway API support provides a standard ingress model across clouds
- ClusterMesh enables future cross-cluster service discovery without L3 routing
- Single CNI to learn, debug, and operate regardless of cloud

**Negative:**

- BYOCNI adds deployment complexity — clusters cannot schedule any pods until Cilium is installed,
  requiring strict ordering (see ADR-009)
- Cloud-specific tuning still exists (e.g. the optional ENI/native override on AWS, masquerade-interface
  globs) — the "single module" carries cloud-conditional logic (the Azure/GCP branches exist but are
  dormant today)
- A Cilium upgrade affects every cluster on that cloud at once (today: the AWS clusters) — mitigated by
  testing in the platform environment before preprod/prod
- Hubble TLS using `helm` method means certificates are not integrated with the platform's
  cert-manager infrastructure

**Risks:**

- Cilium is a critical-path dependency. If a Cilium upgrade introduces a regression, all clusters
  are affected. Mitigated by pinning chart versions and testing upgrades in the platform environment
  before promoting to preprod/prod.
- The overlay datapath decouples pod IPs from VPC subnet capacity (pods draw from the dedicated
  `10.240.0.0/16` pod CIDR), so the node subnet only sizes node/ENI IPs. If a cluster ever opts into
  ENI/native mode, pod IP allocation would then be tied to VPC subnet capacity and large clusters could
  exhaust subnet IPs — size the node subnet accordingly before making that switch.
