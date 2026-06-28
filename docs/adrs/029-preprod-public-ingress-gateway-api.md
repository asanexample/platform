# ADR-029: Preprod Public Ingress via Gateway API

**Date:** 2026-05-27

**Status:** Accepted

## Context

Preprod applications need internet-facing ingress for external testing, stakeholder demos, and
integration testing with third-party services. The platform cluster uses an internal NLB for its
Gateway API ingress — ArgoCD and other platform services are only reachable through the Tailscale
VPN (ADR-010, ADR-011). This is correct for platform-level infrastructure services where access
should be restricted to the platform team.

Preprod has fundamentally different access requirements. External stakeholders reviewing features,
QA teams running browser-based tests, and third-party webhook integrations all need to reach
preprod services over the public internet without VPN enrollment. Requiring Tailscale for every
person who needs to view a staging deployment creates friction that slows the development cycle.

The platform already uses Cilium Gateway API with GatewayClass `cilium` (ADR-017). The shared
`gateway` module (`infra/modules/gateway/`) supports an `internal` boolean variable
that controls the NLB scheme via the `service.beta.kubernetes.io/aws-load-balancer-scheme`
annotation on the Gateway's infrastructure block. The platform live unit sets `internal = true`;
the question is what the preprod live unit should use.

Key constraints:

1. **No production data in preprod.** Preprod uses synthetic test data. Public exposure does not
   risk production data leakage.
2. **Separate DNS zone.** Preprod uses `preprod.aws.refplat.org` (ADR-030), isolated from the
   platform's `aws.refplat.org` zone. Public DNS resolution for preprod services does not affect
   the platform's internal-only DNS posture.
3. **Cilium NetworkPolicy enforcement.** All clusters run Cilium (ADR-008) with network policies
   that restrict pod-to-pod traffic. Public ingress only exposes what is explicitly routed through
   the Gateway — pods without HTTPRoutes are unreachable from the NLB.
4. **Module reuse.** The `gateway` module already parameterizes the NLB scheme. No new module
   code is needed for either internal or public ingress.

### Alternatives Considered

**1. Internal NLB + Tailscale VPN (same as platform).** Deploy the Gateway with `internal = true`
and require all preprod access through Tailscale. This maximizes security parity with the platform
cluster. Rejected: the primary purpose of preprod is external validation. Requiring VPN enrollment
for stakeholders, QA contractors, and webhook providers defeats the purpose of having a pre-
production environment distinct from local dev. The friction of distributing Tailscale invites and
managing VPN access for non-engineering users outweighs the security benefit, especially given that
preprod holds no production data.

**2. Public NLB with Cilium Gateway API (chosen).** Deploy the Gateway with `internal = false`,
using the same `gateway` module with different input values. The NLB is internet-facing, TLS
is terminated at the Gateway via Let's Encrypt DNS-01 (cert-manager + Route53), and services are
accessible at `*.preprod.aws.refplat.org`. This is the simplest approach — one variable change
in the live unit, full reuse of existing module code and patterns.

**3. CloudFront distribution + ALB origin.** Place CloudFront in front of an ALB for caching, WAF
integration, and DDoS protection. Rejected: introduces CloudFront distribution management,
origin access control, and a separate ALB alongside the Cilium Gateway. The additional complexity
is not justified for a preprod environment that serves low-traffic staging deployments, not
production user traffic.

**4. Cloudflare Tunnel.** Run `cloudflared` as a deployment in the cluster, tunneling traffic from
Cloudflare's edge to in-cluster services. Rejected: introduces an external dependency (Cloudflare
account, tunnel credentials) and a different traffic path than what production will use. The
platform's ingress architecture is Cilium Gateway API — preprod should validate the same stack that
production will run, not a different ingress mechanism.

## Decision

Deploy a public internet-facing NLB via Cilium Gateway API on the preprod cluster. The preprod
`gateway` live unit sets `internal = false` (the module default), while the platform live
unit retains `internal = true`.

### Implementation

The preprod `gateway-config` Terragrunt unit at
`infra/live/aws/preprod/us-east-1/platform/gateway-config/terragrunt.hcl` configures:

```hcl
inputs = {
  create   = true
  domain   = "preprod.aws.refplat.org"
  internal = false

  gateway_name = "preprod-gateway"

  letsencrypt_email      = include.base.locals.admin_email
  route53_hosted_zone_id = dependency.route53.outputs.zone_id
  route53_region         = include.base.locals.region

  routes = {}
}
```

Key differences from the platform unit:

| Setting | Platform | Preprod |
|---------|----------|---------|
| `domain` | `aws.refplat.org` | `preprod.aws.refplat.org` |
| `internal` | `true` | `false` |
| `gateway_name` | `platform-gateway` | `preprod-gateway` |
| `routes` | ArgoCD route | Empty (app teams add routes) |

### Gateway Configuration

The Gateway resource uses a wildcard HTTPS listener (`*.preprod.aws.refplat.org`) with
`allowedRoutes.namespaces.from = "All"`, allowing HTTPRoutes from any namespace to attach. This
enables application teams to create their own HTTPRoutes in their team namespaces without
modifying the Gateway resource itself — the role-oriented design benefit of Gateway API (ADR-017).

The HTTP listener (port 80) serves only as a 301 redirect to HTTPS. No plaintext HTTP traffic
reaches backend services.

### TLS

TLS certificates are provisioned by cert-manager using Let's Encrypt with DNS-01 validation
against the preprod Route53 zone (`preprod.aws.refplat.org`, ADR-030). cert-manager's IRSA role
is scoped to the preprod account's Route53 zone ARN only — it cannot modify DNS records in the
platform account's zone (ADR-018, ADR-026).

Cilium's Gateway API implementation requires the TLS secret to also exist in the `cilium-secrets`
namespace with the naming convention `<source-namespace>-<secret-name>` (e.g.,
`cilium-secrets/default-preprod-gateway-tls` for a Gateway in the `default` namespace). This is
how Cilium's Envoy SDS discovers certificates. The gateway-config module must handle this copy.

### Network Policy Requirements

Cilium's external Envoy proxy uses the reserved `ingress` identity (identity 8) for upstream
connections to backend pods — not the `host` identity, despite running with `hostNetwork` (see
ADR-008). Tenant namespaces must have a CiliumNetworkPolicy allowing `fromEntities: ["ingress"]`
in addition to the standard Kubernetes NetworkPolicy allowing traffic from the gateway namespace.
The tenant module (ADR-027) creates both policies automatically.

### No ArgoCD Dependency

Unlike the platform unit, the preprod gateway-config does not depend on an ArgoCD unit and starts
with an empty `routes` map. ArgoCD is not deployed in preprod — applications are deployed by
ArgoCD in the platform cluster targeting the preprod cluster via `argocd-clusters` (ADR-021).
Application HTTPRoutes will be added as teams onboard.

### Dependency Chain

The preprod gateway-config depends on: EKS, Cilium (GatewayClass), cert-manager, external-dns,
and Route53. This mirrors the platform dependency chain minus ArgoCD.

## Consequences

### Positive

- External stakeholders and QA teams access preprod applications directly via browser — no VPN
  enrollment, no Tailscale client installation, no access management overhead
- Full reuse of the gateway-config module — no new Terraform code, only different input values
  in the live unit
- Same ingress architecture (Cilium Gateway API) that production will use — preprod validates
  the real traffic path, not a substitute
- Role-oriented Gateway API design allows app teams to self-service their own HTTPRoutes without
  platform team intervention
- TLS enforced on all routes via cert-manager automation — no plaintext exposure

### Negative

- Preprod services are internet-reachable, increasing the attack surface compared to an internal-
  only NLB. Any vulnerability in an exposed application is reachable from the public internet.
- The public NLB has an AWS-assigned DNS name and a public IP, which may appear in internet-wide
  scanners (Shodan, Censys). Automated scanning tools will probe the endpoint.
- Different NLB scheme between platform (`internal`) and preprod (`public`) means the two
  environments are not identical in their network posture. This is an intentional trade-off, not
  a drift issue, but it must be understood when reasoning about security boundaries.

### Risks

- A vulnerable preprod application could be exploited from the internet. Mitigated by: Cilium
  NetworkPolicy restricting lateral movement, no production data in preprod (synthetic test data
  only), and the ability to quickly set `internal = true` if needed.
- Wildcard listener (`*.preprod.aws.refplat.org`) means any HTTPRoute can attach and claim any
  hostname — including another team's or a platform service's. **Mitigated (Phase 5, ADR-014):** the
  Kyverno `restrict-route-hostnames-team-<t>` policies enforce a per-team hostname allow-list (from
  `teams.hcl`) on HTTPRoute/GRPCRoute/TLSRoute in tenant namespaces, denying cross-team/platform
  hostnames and empty hostname lists. Per-team allow-lists are the ingress analog of per-team image
  isolation.
- The `routes = {}` empty map means the Gateway initially serves no traffic. If teams deploy
  HTTPRoutes via ArgoCD manifests rather than through the Terragrunt unit's `routes` input, the
  Terraform state will not track those routes. This is expected — the `routes` input is for
  platform-managed routes; team routes are managed via GitOps.
