# ADR-017: Gateway API over Traditional Ingress

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform needs to expose HTTP/HTTPS services running on Kubernetes clusters to external
traffic. Kubernetes offers two models for this:

1. **Ingress** — the original Kubernetes API for HTTP routing. Requires a third-party Ingress
   controller (nginx-ingress, traefik, HAProxy, etc.) to implement the actual load balancing.
   The Ingress API is limited: no support for TCP/UDP routing, no standardized TLS policy, no
   header-based routing without controller-specific annotations.

2. **Gateway API** — the successor to Ingress, designed by the Kubernetes SIG-Network community.
   Provides a richer, more expressive routing model with standardized resources: GatewayClass,
   Gateway, HTTPRoute, TLSRoute, TCPRoute. Supports role-oriented design (infra team manages
   Gateway, app teams manage Routes).

The platform already uses Cilium as its CNI (ADR-008). Cilium includes a native Gateway API
implementation — it can serve as the GatewayClass provider without an additional ingress
controller deployment.

### Alternatives Considered

**1. nginx-ingress controller.** The most widely deployed Ingress controller. Mature, well-
documented, large community. However, it requires a separate Deployment + Service + LoadBalancer,
adds another component to manage and upgrade, and uses the limited Ingress API (requiring
nginx-specific annotations for anything beyond basic routing). Using nginx alongside Cilium means
running two L7 proxies in the data path.

**2. Traefik.** Modern ingress controller with native Kubernetes CRD support (IngressRoute).
Better routing model than nginx, auto-discovers services, built-in Let's Encrypt. However, like
nginx, it's a separate deployment that duplicates L7 functionality already available in Cilium.
Traefik's CRDs are vendor-specific, not a Kubernetes standard.

**3. AWS ALB Ingress Controller (now AWS Load Balancer Controller).** Uses AWS ALB/NLB as the
ingress proxy, eliminating in-cluster proxy overhead. Tight AWS integration. However, it's
AWS-specific — not usable on Azure or GCP — and still uses the Ingress API with AWS-specific
annotations. Breaks the cross-cloud consistency goal.

**4. Cilium Gateway API (chosen).** Cilium's built-in Gateway API implementation uses Envoy
proxies managed by Cilium. No additional controller deployment needed. Standard Kubernetes
Gateway API resources (Gateway, HTTPRoute) work across any GatewayClass provider, so the
routing configuration is portable if the platform ever switches CNIs. Cilium handles the
GatewayClass, and the `gateway-config` module creates Gateway and HTTPRoute resources.

## Decision

Use Kubernetes Gateway API with Cilium as the GatewayClass provider for all HTTP/HTTPS service
exposure. The `gateway-config` module (`infra/modules/gateway-config/`) creates the necessary
Gateway API resources and integrates with cert-manager for TLS.

### Architecture

```text
Internet → Cloud Load Balancer (NLB/ALB)
  → Cilium Envoy Proxy (Gateway)
  → HTTPRoute → Backend Service → Pod
```

Cilium's Gateway API implementation provisions Envoy proxy instances to handle Gateway resources.
These proxies are managed by Cilium's control plane and share the same eBPF dataplane used for
pod-to-pod networking.

**Per-cluster exposure:** the **platform** gateway uses an **internal** NLB (reachable only via
Tailscale); **preprod** uses a **public** NLB ([ADR-029](029-preprod-public-ingress-gateway-api.md)).

**Cilium gotcha:** the Gateway's Envoy connects to backends with the reserved Cilium `ingress` identity
(8), which a *standard* k8s NetworkPolicy `from:` **cannot** match. Tenant CiliumNetworkPolicies
receiving Gateway traffic must allow `fromEntities: ["ingress"]` (see
[ADR-008](008-cilium-as-cross-cloud-cni.md); the `gateway-config` and `observability` modules rely on
this).

### Gateway Configuration Module

The `gateway-config` module creates three types of resources:

1. **ClusterIssuer** — cert-manager Let's Encrypt issuer using Route53 DNS01 validation (for
   automated TLS certificate provisioning)
2. **Gateway** — Cilium GatewayClass with TLS termination, referencing cert-manager certificates
3. **HTTPRoute** — per-hostname routing rules directing traffic to backend services, plus HTTP-to-
   HTTPS redirect routes

```hcl
resource "kubernetes_manifest" "gateway" {
  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata   = { name = "platform-gateway" }
    spec = {
      gatewayClassName = "cilium"
      listeners = [
        { name = "https", port = 443, protocol = "HTTPS", tls = { ... } },
        { name = "http",  port = 80,  protocol = "HTTP" }
      ]
    }
  }
}
```

### TLS Integration

TLS certificates are provisioned by cert-manager using Let's Encrypt with DNS01 validation via
Route53. The ClusterIssuer, Gateway, and HTTPRoutes are all managed by the same module, ensuring
the TLS chain is consistent.

### Dependency Chain

The `gateway-config` unit depends on: EKS (cluster), Cilium (Gateway API CRDs + GatewayClass),
cert-manager (ClusterIssuer), external-dns (DNS record creation), ArgoCD (if routes point to
ArgoCD), and Route53 (hosted zone for DNS01 validation). This makes it a leaf node in the
deployment DAG.

## Consequences

**Positive:**

- No additional ingress controller to deploy, configure, upgrade, or monitor — Cilium handles it
- Standard Kubernetes API — Gateway and HTTPRoute resources are portable across GatewayClass
  providers
- Role-oriented design — platform team manages the Gateway (ports, TLS, listeners), app teams can
  manage their own HTTPRoutes
- Integrated TLS via cert-manager — automated certificate provisioning and renewal
- Cross-cloud consistency — the same Gateway API resources will work on Azure (AKS) and GCP when those
  clouds land

**Negative:**

- Gateway API is newer than Ingress — less community documentation, fewer examples, some tooling
  (Helm charts, tutorials) still defaults to Ingress resources
- Cilium's Gateway API implementation uses Envoy, which adds resource overhead compared to
  iptables-based routing (though Envoy provides L7 visibility and policy that iptables cannot)
- Dependency on Cilium for both CNI and ingress creates a single point of failure — a Cilium
  issue affects both pod networking and external traffic routing
- The `gateway-config` module has many dependencies (6 upstream units), making it the most
  complex leaf node in the deployment DAG

**Risks:**

- If Cilium's Gateway API implementation has a bug or limitation that blocks a routing
  requirement, the fallback is to deploy a separate Gateway API controller (e.g., Envoy Gateway,
  Contour) as an additional GatewayClass. The HTTPRoute resources would work unchanged — only
  the Gateway's `gatewayClassName` would change.
- Gateway API is GA for HTTPRoute but some features (TCPRoute, GRPCRoute) are still in beta.
  The platform currently only uses HTTPRoute, so this is not an immediate concern.
