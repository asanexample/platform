# ADR-022: DNS Architecture — Route53 with Cloudflare Delegation

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform needs DNS for two purposes:

1. **Service exposure.** Platform services (ArgoCD, Grafana, future tenant applications) need
   DNS names that resolve to the Gateway API load balancer. These records must be created and
   updated automatically as services are deployed.

2. **Certificate validation.** cert-manager uses DNS01 challenges to prove domain ownership for
   Let's Encrypt TLS certificates. This requires the ability to create TXT records in the DNS zone
   programmatically.

The organization's primary domain is managed on Cloudflare. The platform uses a subdomain (e.g.,
`aws.refplat.org`) for its services. The question is where to host the authoritative DNS for this
subdomain and how to integrate it with automated record management.

### Alternatives Considered

**1. Cloudflare as authoritative for everything.** Keep the subdomain on Cloudflare. Use the
Cloudflare provider in Terraform and the Cloudflare webhook for cert-manager DNS01 challenges.
This is the simplest approach — one DNS provider. However, Cloudflare's DNS API requires an API
token with zone-write permissions, and the cert-manager Cloudflare webhook is a community-
maintained project (not official). More importantly, external-dns supports Cloudflare but its
integration is less mature than the Route53 integration, which is a first-class provider.

**2. Route53 as authoritative for everything.** Transfer the entire domain to Route53. Maximum AWS
integration — Route53 is native to external-dns, cert-manager, and IRSA. However, the parent
domain is on Cloudflare for good reasons (CDN, WAF, DDoS protection for non-platform services),
and transferring it would disrupt existing configurations.

**3. Route53 for subdomain with Cloudflare NS delegation (chosen).** Create a Route53 hosted zone
for the platform's subdomain. Delegate from Cloudflare by creating NS records pointing to
Route53's nameservers. Platform services use Route53 for all DNS operations — external-dns creates
A/CNAME records, cert-manager creates TXT records for DNS01 challenges. The parent domain stays on
Cloudflare.

## Decision

Use Route53 as the authoritative DNS for the platform subdomain, with NS delegation from the
Cloudflare parent zone.

### Architecture

```text
Cloudflare (parent zone: refplat.org)
  └── NS records for aws.refplat.org → Route53 nameservers

Route53 (hosted zone: aws.refplat.org)
  ├── A records → Gateway API load balancer (created by external-dns)
  ├── TXT records → ACME DNS01 challenges (created by cert-manager)
  └── CNAME records → service aliases
```

### Implementation

Three Terragrunt units manage the DNS infrastructure:

1. **`route53`** — Creates the Route53 hosted zone for the subdomain. Outputs the hosted zone ID
   and nameserver list. This is an early dependency in the deployment DAG — cert-manager,
   external-dns, and gateway-config all need the zone ID.

2. **`cloudflare-dns`** — Uses the `cloudflare/dns_delegation` module to create NS records in the
   Cloudflare parent zone pointing to Route53's nameservers. Depends on `route53` for the
   nameserver list.

3. **`external-dns`** — Deploys the external-dns controller with Route53 as the DNS provider.
   Uses IRSA (ADR-018) with Route53 write permissions scoped to the hosted zone.

### cert-manager Integration

cert-manager's ClusterIssuer (configured in the `gateway` module) uses Route53 DNS01
validation:

```yaml
solvers:
  - dns01:
      route53:
        region: us-east-1
        hostedZoneID: <zone-id>
```

cert-manager uses IRSA for Route53 access, scoped to the same hosted zone.

### external-dns Integration

external-dns watches Gateway API HTTPRoute resources and Service resources with the appropriate
annotations. When a new route is created, external-dns automatically creates the corresponding
DNS record in Route53.

## Consequences

**Positive:**

- Route53 is the native DNS provider for AWS tooling — external-dns and cert-manager have
  first-class, well-tested Route53 support
- IRSA provides fine-grained, per-service-account DNS access — cert-manager and external-dns
  each have their own IAM role scoped to the specific hosted zone
- NS delegation is clean — the parent domain stays on Cloudflare with its CDN and WAF benefits,
  while the platform subdomain has full AWS-native DNS automation
- Adding new DNS records is automatic — deploying a new HTTPRoute triggers external-dns to create
  the A record and cert-manager to provision the TLS certificate

**Negative:**

- Two DNS providers to manage — Cloudflare for the parent zone, Route53 for the subdomain.
  The NS delegation is a one-time setup, but it's still two systems to understand.
- Route53 hosted zone costs $0.50/month per zone plus per-query charges. Negligible cost but
  worth noting.
- DNS propagation through the delegation chain can add latency to initial resolution — clients
  must follow the NS delegation from Cloudflare to Route53. Mitigated by standard DNS caching.
- The Cloudflare NS delegation must be created before any cert-manager or external-dns operations
  work. This creates a bootstrapping dependency that requires the Cloudflare API token to be
  available.

**Risks:**

- If the Cloudflare NS delegation is accidentally deleted, the entire platform subdomain stops
  resolving. Mitigated by the delegation being managed in Terraform state (the `cloudflare-dns`
  unit) and Cloudflare's API audit logging.
- Route53 zone deletion would break all platform DNS. The zone is managed in Terraform state (the
  `route53` unit), so deletion requires a deliberate apply/destroy and is visible in plan review.
  Note the zone intentionally uses `force_destroy = var.force_destroy` and **no `prevent_destroy`**
  — the reference platform is designed to be torn down and rebuilt cleanly (see the planned-rebuild
  posture), so the mitigation is IaC review and state, not a hard deletion lock. A long-lived
  production deployment would set `prevent_destroy` and enable registrar/zone safeguards.
