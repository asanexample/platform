# CIDR Allocation Strategy

## Overview

The platform uses a hierarchical CIDR allocation strategy to organize IP address spaces across multiple cloud providers, regions, and environments. Each environment gets a full /16 block, ensuring non-overlapping address spaces that support Transit Gateway routing and cross-cloud VPN connectivity.

## Allocation Hierarchy

1. **Cloud Provider Level**: Each cloud gets a range of /16 blocks
2. **Environment Level**: Each environment gets a dedicated /16
3. **Region Level**: Each region within an environment gets a /21
4. **Availability Zone Level**: Each AZ within a region gets a /24
5. **Subnet Level**: Each AZ is subdivided into 6 specialized tiers

## Address Space Allocation

### Cloud Provider Allocation

| Cloud | Environment range | Summary route |
|-------|------------------|---------------|
| AWS | `10.100.0.0/16` – `10.102.0.0/16` | `10.100.0.0/14` |
| Azure | `10.104.0.0/16` – `10.106.0.0/16` | `10.104.0.0/14` |
| GCP | `10.108.0.0/16` – `10.110.0.0/16` | `10.108.0.0/14` |

Each cloud has room for 4 environments within its /14 summary route, with gaps between clouds for future expansion.

### Environment Allocation

Each environment gets a full /16, giving 32 regional /21 blocks — enough for any realistic multi-region deployment without needing secondary CIDRs.

#### AWS

| Environment | VPC CIDR | Status |
|-------------|----------|--------|
| Platform | `10.100.0.0/16` | Deployed |
| Preprod | `10.101.0.0/16` | Deployed (networking only) |
| Prod | `10.102.0.0/16` | Deployed (networking only) |
| Reserved | `10.103.0.0/16` | — |

#### Azure

| Environment | VNet CIDR | Status |
|-------------|-----------|--------|
| Dev | `10.104.0.0/16` | Deployed |
| Ops | `10.101.24.0/21` | Deployed (does not follow /16 scheme -- see note) |
| Preprod | `10.105.0.0/16` | Planned |
| Prod | `10.106.0.0/16` | Planned |
| Reserved | `10.107.0.0/16` | — |

> **Note:** Azure ops/westus uses `10.101.24.0/21`, which falls in the
> AWS CIDR range and uses a /21 instead of a /16. This predates the
> current allocation scheme. It should be migrated to the
> `10.104.0.0/14` range when the environment is rebuilt.

#### GCP

| Environment | VPC CIDR | Status |
|-------------|----------|--------|
| Ops | `10.102.0.0/16` | Scaffolded (does not follow scheme -- see note) |
| Dev | `10.108.0.0/16` | Planned |
| Preprod | `10.109.0.0/16` | Planned |
| Prod | `10.110.0.0/16` | Planned |
| Reserved | `10.111.0.0/16` | — |

> **Note:** GCP ops uses `10.102.0.0/16`, which overlaps with AWS prod.
> This predates the current allocation scheme. It should be migrated to
> the `10.108.0.0/14` range before cross-cloud connectivity is enabled.

### Region Allocation

Each region within an environment gets a /21 (2048 IPs, 8 AZ-level /24 blocks). Regions are assigned sequentially within the /16:

| Region offset | CIDR (within /16) |
|---------------|-------------------|
| Region 1 | `.0.0/21` |
| Region 2 | `.8.0/21` |
| Region 3 | `.16.0/21` |
| Region 4 | `.24.0/21` |
| ... | (up to 32 regions) |

Example for AWS Platform (us-east-1):

- Region block: `10.100.0.0/21`
- AZ1: `10.100.0.0/24`, AZ2: `10.100.1.0/24`, AZ3: `10.100.2.0/24`

### Subnet Tiers

Each AZ /24 is subdivided into 6 specialized tiers:

| Tier | Size | Usable IPs | Purpose |
|------|------|-----------|---------|
| Kubernetes | /26 | 62 | EKS/AKS/GKE worker nodes |
| Endpoints | /26 | 62 | VPC endpoints, private link |
| Firewall | /26 | 62 | Network firewall (reserved) |
| Services | /27 | 30 | Internal services, load balancers |
| Public | /28 | 14 | IGW-routed, ALBs, NAT gateways |
| Transit | /28 | 14 | Transit Gateway / VPN attachments |

Subnets are computed from the VPC CIDR using `cidrsubnet()` — no manual calculation required. Each environment's `network.hcl` specifies only `vpc_cidr` and `azs`; the subnet map is auto-generated.

## Kubernetes Network CIDRs

Kubernetes overlay networks use separate, non-routable CIDR ranges:

| Purpose | CIDR | Notes |
|---------|------|-------|
| Pod CIDR | `10.240.0.0/16` | Cilium VXLAN overlay — not routed on VPC |
| Service CIDR | `10.241.0.0/16` | Cluster-internal only |
| DNS Service IP | `10.241.0.10` | Within service CIDR |

These ranges are shared across clusters (overlay isolation prevents collision). Cross-cluster pod communication uses Cilium ClusterMesh at L7, not L3 routing.

## Authoritative CIDR Sources

Each region's `network.hcl` file is the authoritative source of CIDR allocations. These files live alongside the region's `region.hcl` (e.g., `infra/live/aws/platform/us-east-1/network.hcl`) and are loaded by `_base.hcl` into every module's configuration.

## Cross-Cloud Connectivity

The allocation strategy ensures all VPC/VNet CIDRs are non-overlapping across clouds:

- AWS `10.100.0.0/14` and Azure `10.104.0.0/14` and GCP `10.108.0.0/14` have no overlap
- Site-to-Site VPN or interconnect between clouds can use summary routes
- Transit Gateway within AWS connects VPCs using per-environment /16 routes

## Next Steps

Continue to [Network Topology](07-network-topology.md) for details on network architecture and connectivity patterns.
