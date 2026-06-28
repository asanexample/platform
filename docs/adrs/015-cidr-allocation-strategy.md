# ADR-015: CIDR Allocation Strategy

**Date:** 2026-05-23

**Status:** Accepted

## Context

The platform is multi-cloud by design but **AWS-first** today (Azure/GCP deferred —
[ADR-001](001-multi-cloud-terragrunt-structure.md)), with multiple environments (platform, preprod,
prod) and multiple regions per environment. Each environment needs a VPC with non-overlapping address
space, and cross-cloud VPN connectivity is on the roadmap — so the scheme reserves **globally
non-overlapping** CIDRs across all (current and future) clouds from the start, even though only AWS is
deployed.

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
/21 allocation. The AWS rows are live; the Azure/GCP rows are **reserved** for when those clouds land.

### Subnet Tier Scheme

Each **AZ** gets a /24 (256 IPs) carved from the environment's /16 (`cidrsubnet(vpc_cidr, 8, az_idx)`);
within each AZ's /24 the 6 tiers below are carved by `newbits`/`netnum` (18 subnets total across 3 AZs).
The `Bits` column is relative to the AZ's /24 parent:

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

Kubernetes overlay networks use separate, non-routable ranges. Pod CIDRs are **per-cluster and
non-overlapping** — each a /16 from the reserved `10.240.0.0/14` pod supernet (ClusterMesh-ready) — not
a single range shared across clusters. The Service CIDR is the EKS cluster default:

| Purpose | CIDR |
|---------|------|
| Pod supernet (reserved) | `10.240.0.0/14` |
| Pod CIDR — platform | `10.240.0.0/16` |
| Pod CIDR — preprod | `10.241.0.0/16` |
| Pod CIDR — prod (reserved) | `10.242.0.0/16` |
| Service CIDR (EKS default) | `172.20.0.0/16` |
| DNS Service IP | `172.20.0.10` |

Pod traffic is VXLAN-encapsulated by Cilium (the overlay datapath) and never appears on the VPC/VNet
routing table; the Service CIDR is virtual, handled by Cilium's kube-proxy replacement.

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
- The scheme reserves space for clouds not yet deployed (Azure/GCP). If their eventual real-world
  ranges don't match the reservation they'll need reconciling — but with those clouds removed today,
  there are no live off-scheme exceptions.

**Risks:**

- The reserved per-cloud /14s are non-overlapping, so AWS, Azure, and GCP environments won't collide
  when the latter two are added. (The earlier Azure/GCP scaffolding had an off-scheme overlap — GCP at
  `10.102.0.0/16` colliding with AWS prod — but it has been removed.) Re-validate the allocation table
  before establishing cross-cloud VPN.
- If the platform grows beyond 4 environments per cloud, the /14 allocation is exhausted. Mitigated
  by the fact that 4 environments per cloud is sufficient for the foreseeable roadmap, and adjacent
  /14 blocks are available if needed.
