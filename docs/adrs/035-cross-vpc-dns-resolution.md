# ADR-035: Cross-VPC DNS Resolution for Private EKS Endpoints

**Date:** 2026-05-28

**Status:** Accepted

## Context

EKS clusters with private-only API endpoints (ADR-010) expose DNS names (e.g.,
`*.gr7.us-east-1.eks.amazonaws.com`) that resolve to private IP addresses within the cluster's
VPC. When a workload in one VPC needs to reach an EKS API in a different VPC -- such as ArgoCD
in the platform VPC managing workloads on the preprod EKS cluster -- DNS resolution fails.

The platform and preprod VPCs are connected via Transit Gateway, so IP-level connectivity
exists. The problem is purely DNS: the platform VPC's Route53 resolver has no record for the
preprod EKS endpoint, so the query returns the public DNS response (which points at IPs
unreachable from a private-only cluster).

AWS creates a Route53 Private Hosted Zone for each private EKS endpoint, but these PHZs are
managed internally by EKS and are not accessible via standard Route53 APIs. They cannot be
listed, exported, or associated with additional VPCs. This means the straightforward solution
-- associating the EKS-managed PHZ with the platform VPC -- is impossible.

### Alternatives Considered

**1. Route53 Resolver endpoints (outbound + inbound).** Deploy an inbound Resolver endpoint
in the preprod VPC and an outbound Resolver endpoint in the platform VPC with forwarding rules
that send `*.eks.amazonaws.com` queries to the inbound endpoint's IPs. DNS queries from the
platform VPC are forwarded over Transit Gateway to the preprod VPC's resolver, which has access
to the EKS-managed PHZ and returns the correct private IPs. This is the most robust approach --
fully automatic, no IP maintenance required -- but costs approximately $365/month for the 4
ENIs (2 per endpoint, minimum 2 AZs each). It also requires deploying a `cross-vpc-dns` unit
in both VPCs (inbound in preprod, outbound in platform).

**2. Custom PHZ with static A records.** Create a Private Hosted Zone in the platform VPC for
the preprod EKS endpoint domain and manually populate it with the EKS API server's ENI IPs.
This costs effectively nothing (Route53 PHZ + a few records) and works immediately. However,
the ENI IPs are not stable -- they change when EKS replaces the control plane (e.g., during
cluster version upgrades or certain configuration changes). Each time this happens, someone
must discover the new IPs and update the records.

**3. Custom PHZ with dynamic ENI IP lookup (chosen).** Same as option 2, but instead of
hardcoding IPs, use a Terraform `external` data source that runs a bash script at plan/apply
time to query the EC2 API for the current EKS ENI IPs. The script filters
`describe-network-interfaces` by the description field (`Amazon EKS <cluster-name>`) and
status (`in-use`), returning the private IPs. For cross-account lookups, the script assumes
an IAM role in the target account before querying. This approach is cheap (just a PHZ) and
automatic on each `terragrunt apply`, eliminating the manual IP maintenance burden of option 2.

## Decision

Use the custom PHZ approach with dynamic ENI IP lookup (`dns_method = "phz"`). The module
(`infra/modules/aws/cross-vpc-dns/`) supports all three approaches via a `dns_method` variable
that accepts `phz`, `resolver_outbound`, or `resolver_inbound`, allowing future migration
without replacing the module.

### Implementation

The module's PHZ mode works as follows:

1. **Dynamic IP resolution.** For each `phz_records` entry that specifies an `eks_cluster_name`
   (and no static `ips`), the module invokes an `external` data source. The embedded bash script
   optionally assumes a cross-account IAM role (`eks_lookup_role_arn`), then calls
   `aws ec2 describe-network-interfaces` filtering on the EKS cluster name. The returned ENI
   private IPs become the A record values.

2. **Private Hosted Zone creation.** A Route53 PHZ is created for each record's domain (the
   EKS endpoint FQDN, extracted by stripping `https://` from the cluster endpoint output). The
   PHZ is associated with the platform VPC so that DNS queries from within that VPC resolve to
   the private IPs.

3. **A records.** Each PHZ gets an A record pointing at the dynamically resolved (or statically
   provided) IPs with a configurable TTL (default 60 seconds).

The live unit (`infra/live/aws/platform/us-east-1/platform/cross-vpc-dns/terragrunt.hcl`)
configures a single PHZ record for the preprod EKS cluster, using the `PlatformDeployer` role
in the preprod account (<PREPROD_ACCOUNT_ID>) for cross-account ENI lookup. It depends on the platform
`networking` module (for VPC ID) and the preprod `eks` module (for cluster endpoint and name).

### Resolver Mode

The module retains full Resolver endpoint support for future use. Switching requires:

- Deploying a `cross-vpc-dns` unit in the preprod VPC with `dns_method = "resolver_inbound"`
- Changing the platform unit to `dns_method = "resolver_outbound"` with forwarding rules
  targeting the inbound endpoint IPs
- The Terragrunt unit has a commented-out dependency block for this configuration

## Consequences

### Positive

- Zero ongoing cost beyond the Route53 PHZ ($0.50/month per hosted zone)
- IPs are resolved dynamically at apply time -- no manual maintenance when ENIs change
- Single module supports all three DNS methods via a toggle, simplifying future migration
- Cross-account role assumption is handled transparently by the data source script
- Works with the existing Transit Gateway connectivity -- no additional network infrastructure

### Negative

- IPs are only updated on `terragrunt apply`. If EKS replaces control plane ENIs between
  applies (e.g., during an upgrade initiated outside Terraform), DNS records become stale
  until the next apply
- The `external` data source relies on `aws` CLI availability and shell execution at plan time,
  which is less portable than pure Terraform resources
- Static IP fallback (`phz_static`) still exists as a code path but provides no automation

### Risks

- **ENI IP changes between applies.** If the preprod EKS control plane is recreated (version
  upgrade, AZ rebalancing), the ENI IPs change. DNS records in the platform VPC will point at
  stale IPs until the cross-vpc-dns unit is re-applied. Mitigated by running the unit as part
  of `terragrunt run --all apply` after any EKS changes, and by the low TTL (60s) ensuring
  clients pick up new records quickly once updated.
- **Cross-account role assumption failure.** If the `PlatformDeployer` role in preprod is
  modified or the trust policy is changed, the ENI lookup script fails and the plan errors.
  This fails loudly (no silent stale data), and the `mock_outputs` on the preprod EKS
  dependency ensure destroy operations still work.
