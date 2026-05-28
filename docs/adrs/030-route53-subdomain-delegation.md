# ADR-030: Route53 Subdomain Delegation for Environment DNS

**Date:** 2026-05-27

**Status:** Accepted

## Context

Each environment needs its own DNS zone for ingress, certificate validation, and service
discovery. The platform account (829808296602) owns the `aws.refplat.org` Route53 hosted zone,
which serves as the authoritative DNS for the platform cluster's Gateway API services (ADR-022).
As the preprod environment (620830101009) adds its own EKS cluster with public ingress (ADR-029),
it needs DNS records under `preprod.aws.refplat.org` — and the question is where that zone lives
and how the DNS tooling authenticates to it.

The platform's DNS architecture relies on two Kubernetes controllers that write DNS records:

1. **cert-manager** — creates TXT records for Let's Encrypt DNS-01 challenges to prove domain
   ownership for TLS certificate provisioning
2. **external-dns** — creates A/CNAME records pointing hostnames to the Gateway API load balancer

Both controllers authenticate to Route53 via IRSA (ADR-018). Each controller's IAM role has a
trust policy scoped to the local cluster's OIDC provider and a permission policy scoped to a
specific Route53 zone ARN. This is the standard per-workload least-privilege pattern.

The problem arises when preprod's cert-manager and external-dns need to manage records in a DNS
zone. If the zone lives in the platform account, preprod's IRSA roles would need cross-account
Route53 access — the IAM role in preprod (620830101009) would need `route53:ChangeResourceRecordSets`
permission on a zone in the platform account (829808296602). This requires:

- A resource-based policy on the platform account's Route53 zone granting cross-account access
- The preprod IRSA role to include `sts:AssumeRole` for a cross-account role, or direct
  cross-account resource policy trust
- CloudTrail events split across two accounts for the same DNS zone

This breaks the IAM isolation pattern established in ADR-026 (cross-account secret isolation)
and ADR-018 (IRSA scoped to local account resources). The same principle applies: each account
should own the resources its workloads operate on.

### Alternatives Considered

**1. Single shared zone in the platform account.** Keep `aws.refplat.org` as the only zone and
create all environment records directly under it (e.g., `app.preprod.aws.refplat.org` as an A
record in the platform zone). Preprod's cert-manager and external-dns would need cross-account
IAM access to the platform account's Route53. Rejected: violates the per-account IAM isolation
pattern. The platform account's Route53 zone becomes a shared resource that multiple accounts
write to, expanding the blast radius. A misconfigured IRSA role in preprod could modify platform
DNS records. CloudTrail correlation across accounts complicates audit. Every new environment adds
another cross-account trust relationship to the platform zone's resource policy.

**2. Subdomain delegation to per-environment zones (chosen).** Create a separate Route53 hosted
zone for `preprod.aws.refplat.org` in the preprod account. Add NS delegation records in the
platform account's `aws.refplat.org` zone pointing to the preprod zone's nameservers. Each
environment's DNS tooling (cert-manager, external-dns) operates on its own account's zone using
IRSA roles scoped to local resources only.

**3. Cloudflare subzones per environment.** Create each environment's subdomain as a separate
zone on Cloudflare, bypassing Route53 entirely for workload environments. Rejected: introduces
a different DNS provider per environment. The platform uses Route53 because it has native IRSA
integration with cert-manager and external-dns (ADR-022). Splitting to Cloudflare for subzones
would require the Cloudflare cert-manager webhook (community-maintained), Cloudflare API tokens
managed as secrets, and a different external-dns provider configuration per environment.

**4. Separate top-level domains per environment.** Register `preprod-refplat.org` or use a
different subdomain structure like `preprod.refplat.org` delegated directly from the Cloudflare
parent zone. Rejected: loses the organizational hierarchy that `*.aws.refplat.org` provides.
The domain structure should reflect the cloud and environment topology. Each top-level delegation
from Cloudflare adds operational overhead and makes the relationship between environments less
obvious.

## Decision

Use Route53 subdomain delegation to give each environment its own hosted zone in its own AWS
account. The platform account's `aws.refplat.org` zone contains NS records pointing subdomains
to the child account's zone nameservers.

### Architecture

```text
Cloudflare (parent zone: refplat.org)
  └── NS records for aws.refplat.org → Route53 (platform account)

Route53 (platform account: 829808296602)
  Zone: aws.refplat.org
  ├── A records (argocd.aws.refplat.org → internal NLB, via external-dns)
  ├── TXT records (ACME challenges, via cert-manager)
  ├── CAA record (restrict issuance to Let's Encrypt)
  └── NS records for preprod.aws.refplat.org → Route53 (preprod account)

Route53 (preprod account: 620830101009)
  Zone: preprod.aws.refplat.org
  ├── A records (*.preprod.aws.refplat.org → public NLB, via external-dns)
  ├── TXT records (ACME challenges, via cert-manager)
  └── CAA record (restrict issuance to Let's Encrypt)

Route53 (prod account: 554518885123)         [future]
  Zone: prod.aws.refplat.org
  ├── A records
  ├── TXT records
  └── CAA record
```

DNS resolution follows the standard delegation chain: Cloudflare resolves `refplat.org`, delegates
`aws.refplat.org` to Route53 in the platform account, which delegates `preprod.aws.refplat.org`
to Route53 in the preprod account. Each hop follows standard NS delegation — no custom resolvers
or forwarding rules.

### Implementation

Three components implement the delegation:

1. **Preprod Route53 zone** (`infra/live/aws/preprod/us-east-1/platform/route53/`) — creates the
   `preprod.aws.refplat.org` hosted zone in the preprod account using the shared `route53` module.
   Includes CAA records restricting certificate issuance to Let's Encrypt (`issue`, `issuewild`,
   `iodef`). Outputs its `name_servers` list for the delegation module to consume.

2. **Route53 delegation module** (`infra/modules/aws/route53_delegation/`) — a minimal module
   that creates NS records in a parent zone. Takes a `parent_zone_id` and a map of subdomain
   FQDNs to nameserver lists. Only creates NS records — CAA, A, and TXT records are managed in
   the child zone by the environment's own DNS tooling.

3. **Route53 delegation live unit** (`infra/live/aws/platform/us-east-1/platform/route53-delegation/`)
   — runs in the platform account (which owns the parent zone) and creates NS records pointing to
   the preprod zone's nameservers. Adding a new environment (e.g., prod) requires one new entry
   in the `delegations` map and a corresponding `dependency` block for the new account's route53
   unit.

### IRSA Scoping

Each environment's cert-manager and external-dns IRSA roles are scoped to their own account's
Route53 zone ARN (e.g., `arn:aws:route53:::hostedzone/<zone-id>`). No IRSA role has cross-account
Route53 access. cert-manager in preprod can create TXT records in `preprod.aws.refplat.org` but
cannot touch `aws.refplat.org` or any other zone.

### TTL Considerations

The delegation module defaults to a 172800-second (48-hour) TTL for NS records — the standard
convention for NS delegation. Nameservers for an AWS hosted zone do not change once created, so
this TTL is acceptable for steady-state operation. If a zone is destroyed and recreated (new
nameservers), the delegation must be updated and the TTL wait applies. The TTL can be lowered
in the live unit's inputs if faster propagation is needed during a migration.

## Consequences

### Positive

- Clean IAM boundaries per environment — cert-manager and external-dns in each account use IRSA
  roles scoped to their own account's Route53 zone. No cross-account Route53 access is needed,
  consistent with the isolation pattern in ADR-026.
- Each account's CloudTrail captures all DNS changes for its own zone — no cross-account event
  correlation needed for DNS audit.
- The delegation module is a reusable pattern — adding `prod.aws.refplat.org` is one new entry
  in the `delegations` map and a new route53 unit in the prod account. No new Terraform code.
- CAA records per zone provide defense-in-depth against unauthorized certificate issuance, even
  if a ClusterIssuer is misconfigured.
- Standard DNS delegation — no custom resolvers, forwarding rules, or Route53 Resolver endpoints
  needed for subdomain resolution.

### Negative

- Two-hop delegation chain (Cloudflare → platform Route53 → preprod Route53) adds one extra DNS
  lookup for preprod domains compared to platform domains. In practice, this adds single-digit
  milliseconds on the first resolution and is cached by recursive resolvers.
- Each new environment requires coordination between two accounts: create the zone in the child
  account, then create the NS delegation in the platform account. The Terragrunt dependency
  graph handles this ordering, but manual deployments must follow the sequence.
- The delegation module runs in the platform account but references the preprod account's route53
  outputs via a cross-environment Terragrunt dependency. This creates a deployment-time coupling:
  the preprod route53 unit must be applied before the platform route53-delegation unit can run.
- Route53 zone costs compound — $0.50/month per hosted zone per environment. At 3 environments
  (platform, preprod, prod) this is $1.50/month, negligible but non-zero.

### Risks

- If the NS delegation records in the platform account are accidentally deleted, the entire
  preprod subdomain stops resolving. Mitigated by the delegation records being in Terraform state
  and the route53-delegation unit having no destroy dependencies from downstream units — it is
  never destroyed as part of a preprod teardown.
- If the preprod Route53 zone is destroyed and recreated, its nameservers change. The delegation
  records in the platform zone must be updated (re-apply the delegation unit) and the 48-hour NS
  TTL must expire before all resolvers see the new nameservers. Mitigated by Terragrunt's
  dependency graph automatically picking up the new nameservers on the next apply, and by the
  preprod zone having `force_destroy = true` to allow clean teardowns.
- A compromised preprod account could modify its own DNS zone to point records at malicious
  endpoints. This is contained to `*.preprod.aws.refplat.org` — the attacker cannot modify
  the parent zone or any other environment's records because the delegation is one-directional
  (parent delegates to child, child cannot write to parent).
