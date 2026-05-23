# ADR-015: CIDR Allocation Strategy

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform operates across three cloud providers (AWS, Azure, GCP) with multiple environments
(platform, preprod, prod) and multiple regions per environment. Each environment needs a VPC/VNet
with non-overlapping address space. Cross-cloud VPN connectivity is planned, which requires the
entire multi-cloud estate to have globally non-overlapping CIDRs.

Without a systematic allocation strategy, CIDR assignment becomes ad-hoc — teams pick ranges that
seem available, overlaps are discovered only when connectivity is attempted, and resizing a VPC
requires re-IPing existing resources.

### Constraints

- VPC/VNet CIDRs cannot overlap within a cloud if cross-environment connectivity (Transit Gateway,
  VNet peering) is needed.
- VPC/VNet CIDRs cannot overlap across clouds if cross-cloud VPN is planned.
- Subnet sizing must accommodate the target workload type: Kubernetes nodes need more IPs than
  endpoint subnets.
- Subnets must span 3 availability zones for high availability.
- AWS has a 5 VPC per region soft limit and various subnet constraints.
- Azure has a 1000 VNet per subscription limit but more flexible subnet sizing.

### Alternatives Considered

**1. Small per-environment CIDRs (/24 or /22).** Allocate small blocks to conserve address space.
This maximizes the number of environments that fit in RFC 1918 space but severely limits subnet
count and size. A /24 VPC cannot fit 6 subnet tiers across 3 AZs (18 subnets). Rejected because
it forces compromises on subnet architecture.

**2. Large per-cloud CIDRs (/8 or /10).** Allocate a single large block per cloud and subdivide
dynamically. Maximum flexibility but no clear allocation hierarchy — regions and environments get
whatever range is next available, making the allocation scheme impossible to reason about without a
spreadsheet. Makes cross-cloud summary routes impossible.

**3. Hierarchical allocation with /14 per cloud and /16 per environment (chosen).** Assign each
cloud a /14 summary block (4 contiguous /16s). Within each cloud, assign each environment a /16.
Within each /16, use a deterministic subnet tier scheme with `cidrsubnet()` to compute per-AZ
subnets from the VPC CIDR and AZ list. No manual CIDR math — adding a new region is a one-line
change to `network.hcl`.

## Decision

Implement a hierarchical CIDR allocation strategy with three levels: cloud, environment, and
subnet tier.

### Cloud-Level Allocation

Each cloud provider gets a /14 summary block (4096 IPs × 4 = 16,384 addresses per cloud):

| Cloud | Summary Route | Environment Range |
|-------|---------------|-------------------|
| AWS | `10.100.0.0/14` | `10.100.0.0/16` – `10.103.0.0/16` |
| Azure | `10.104.0.0/14` | `10.104.0.0/16` – `10.107.0.0/16` |
| GCP | `10.108.0.0/14` | `10.108.0.0/16` – `10.111.0.0/16` |

The /14 summary routes enable simple cross-cloud firewall and routing rules: "allow traffic from
AWS" = `10.100.0.0/14`.

### Environment-Level Allocation

Each environment gets a /16 within its cloud's /14:

| Cloud | Environment | VPC CIDR |
|-------|-------------|----------|
| AWS | Platform | `10.100.0.0/16` |
| AWS | Preprod | `10.101.0.0/16` |
| AWS | Prod | `10.102.0.0/16` |
| Azure | Dev | `10.104.0.0/16` |
| Azure | Prod | `10.106.0.0/16` |
| GCP | Platform | `10.108.0.0/16` |

A /16 provides 65,536 addresses per environment — enough for multiple regions, each with its own
/21 allocation.

### Subnet Tier Scheme

Each region gets a /21 (2,048 IPs) from the environment's /16, subdivided into 6 tiers across
3 availability zones (18 subnets total):

| Tier | Size per AZ | Bits | Purpose |
|------|-------------|------|---------|
| Kubernetes | /26 (62 IPs) | newbits=2 | EKS/AKS worker nodes |
| Endpoints | /26 (62 IPs) | newbits=2 | VPC endpoints, private link |
| Firewall | /26 (62 IPs) | newbits=2 | Network firewall endpoints (reserved) |
| Services | /27 (30 IPs) | newbits=3 | Internal services, NLBs |
| Public | /28 (14 IPs) | newbits=4 | ALBs, NAT gateways, bastion |
| Transit | /28 (14 IPs) | newbits=4 | Transit Gateway, VPN termination |

Subnets are computed from `vpc_cidr` + `azs` using `cidrsubnet()` in each region's `network.hcl`.
The networking module reads these values and creates subnets without manual CIDR math.

### Overlay CIDRs (Kubernetes)

Kubernetes overlay networks use separate, non-routable ranges shared across all clusters:

| Purpose | CIDR |
|---------|------|
| Pod CIDR | `10.240.0.0/16` |
| Service CIDR | `10.241.0.0/16` |
| DNS Service IP | `10.241.0.10` |

These are encapsulated by Cilium (VXLAN or ENI) and never appear on the VPC/VNet routing table.

### Authoritative Source

The authoritative source for CIDR allocation is each region's `network.hcl` file. The subnet tier
structure (`subnet_tiers` map with `newbits` and `netnum` values) is defined there and consumed
by the networking module.

## Consequences

**Positive:**

- Globally non-overlapping CIDRs across all clouds and environments — cross-cloud VPN "just works"
  without address conflicts
- Cloud-level /14 summary routes simplify firewall rules and routing tables
- Deterministic subnet computation via `cidrsubnet()` — no manual CIDR math, no spreadsheets
- Adding a new region requires only creating a `network.hcl` with the VPC CIDR and AZ list
- 6 subnet tiers provide clear separation of concerns (kubernetes nodes, endpoints, public
  resources, transit connectivity)
- Kubernetes overlay CIDRs are isolated from VPC address space

**Negative:**

- /16 per environment is generous — most environments won't use more than a fraction of the 65,536
  addresses. This trades address efficiency for simplicity and growth headroom.
- The scheme assumes 3 AZs per region. Regions with 2 AZs would waste subnet allocations; regions
  with 4+ AZs would need scheme adjustments.
- Pre-existing environments that don't follow the scheme (Azure ops/westus using `10.101.24.0/21`,
  GCP ops using `10.102.0.0/16`) create exceptions that must be documented and accounted for in
  routing rules.

**Risks:**

- The GCP ops environment (`10.102.0.0/16`) overlaps with AWS prod (`10.102.0.0/16`). This
  must be resolved before cross-cloud VPN is established between these environments. Options:
  re-IP the GCP environment or use NAT at the VPN boundary.
- If the platform grows beyond 4 environments per cloud, the /14 allocation is exhausted. Mitigated
  by the fact that 4 environments per cloud is sufficient for the foreseeable roadmap, and adjacent
  /14 blocks are available if needed.
