# Network Topology

## Overview

The platform implements a multi-account network topology with per-environment VPCs. Each environment gets a dedicated /16 CIDR block, and each region within an environment is allocated a /21 block subdivided into 6 specialized subnet tiers across 3 availability zones. AWS is the only deployed cloud today; the CIDR scheme reserves non-overlapping space for Azure/GCP when they land (see [CIDR Allocation](06-cidr-allocation.md)).

## Design Principles

1. **Multi-Cloud Ready**: Non-overlapping CIDRs reserve space across AWS (deployed) and Azure/GCP (planned) to enable cross-cloud VPN and interconnect without renumbering.
2. **Multi-Account Isolation**: Each AWS account has its own VPC — no shared networking between environments.
3. **Topology Flexibility**: Three supported topologies — private (NAT), public (direct IGW), and airgapped (no internet).
4. **Availability Zone Awareness**: Resources distributed across multiple AZs for high availability.
5. **Service Segmentation**: Specialized subnet tiers for different workload types.

## Network Topologies

The networking module supports three distinct topologies, configurable per environment:

### Private (Default)

Standard for production workloads. Nodes in private subnets, NAT gateways provide internet egress.

```text
Internet ─── IGW ─── Public Subnets (ALBs, NAT GWs)
                          │
                     NAT Gateway
                          │
              Private Subnets (EKS nodes, services)
                          │
                    S3 Gateway Endpoint (free, direct to S3)
```

### Public

For dev/sandbox environments where cost matters more than isolation. Nodes get public IPs directly.

```text
Internet ─── IGW ─── Public Subnets (EKS nodes, ALBs)
                          │
                    S3 Gateway Endpoint
```

### Airgapped

For regulated/isolated workloads. No internet access. Requires VPC endpoints for all AWS API access.

```text
              Private Subnets (all resources)
                          │
                VPC Endpoints (STS, ECR, S3, EC2, ELB, CloudWatch, ...)
```

## Subnet Tiers

Each AZ contains 6 specialized subnets:

| Tier | Size | Purpose |
|------|------|---------|
| **Kubernetes** | /26 (62 IPs) | EKS worker nodes. Tagged for EKS auto-discovery. |
| **Endpoints** | /26 (62 IPs) | VPC interface endpoints, private link resources. |
| **Firewall** | /26 (62 IPs) | AWS Network Firewall endpoints (reserved for future use). |
| **Services** | /27 (30 IPs) | Internal services, NLBs, managed service endpoints. |
| **Public** | /28 (14 IPs) | IGW-routed resources: ALBs, NAT gateways, bastion hosts. |
| **Transit** | /28 (14 IPs) | Transit Gateway attachments, VPN termination points. |

Subnets are computed from `vpc_cidr` + `azs` using `cidrsubnet()` in each environment's `network.hcl`. No manual CIDR math required — onboarding a new environment is a one-line change.

## Multi-Account Architecture

### AWS

| Account | Environment | VPC CIDR | Purpose |
|---------|-------------|----------|---------|
| Management (<MGMT_ACCOUNT_ID>) | mgmt | None | Organizations, Identity Center, state backend |
| Platform (<PLATFORM_ACCOUNT_ID>) | platform | `10.100.0.0/16` | Hub EKS cluster, shared services, observability, TGW hub |
| Preprod (<PREPROD_ACCOUNT_ID>) | preprod | `10.101.0.0/16` | Full tenant cluster (EKS, tenants, Kyverno Enforce), TGW spoke |
| Prod (<PROD_ACCOUNT_ID>) | prod | `10.102.0.0/16` | Networking + org scaffolding (no cluster yet) |

### Cross-Account Connectivity

Transit Gateway is **deployed**: the hub lives in the platform account and is shared to spokes via
RAM (ADR-034). The platform↔preprod attachment is live; the prod attachment is planned (prod has
networking but no cluster yet).

```text
            Transit Gateway (hub: platform account)
           /          |            \
    Platform       Preprod          Prod
   10.100/16      10.101/16       10.102/16
   (hub)          (spoke, live)   (attachment planned)
```

Each VPC attaches via its transit subnets (/28 per AZ). TGW route tables control which environments
can reach each other. EKS-managed private hosted zones are inaccessible cross-VPC, so the platform
maintains its own **cross-VPC DNS** (deployed) for resolving preprod cluster endpoints over the TGW.

## Cross-Cloud Connectivity (Planned)

Site-to-Site VPN between clouds, terminating in transit subnets:

```text
AWS (10.100-102/16) ──── VPN ──── Azure (10.104-106/16)
                                       │
                                  VPN ──── GCP (10.108-110/16)
```

Summary routes: AWS `10.100.0.0/14`, Azure `10.104.0.0/14`, GCP `10.108.0.0/14`.

## Security Controls

- **VPC Flow Logs**: Enabled by default on all VPCs (CloudWatch or S3 destination). Required for compliance.
- **S3 Gateway Endpoint**: Automatically created on every VPC (free). Keeps S3 traffic off the NAT/internet path.
- **EKS Security Group**: Created when EKS networking is enabled. Self-referencing inbound, all outbound.
- **Subnet tagging**: Kubernetes and public subnets auto-tagged for EKS load balancer discovery.
- **Private route tables**: One per private subnet for granular routing control.

## Kubernetes Network Integration

Kubernetes clusters use Cilium CNI with overlay networking:

| Setting | Value |
|---------|-------|
| Network plugin | Cilium (installed post-cluster) |
| Pod CIDR | `10.240.0.0/16` (overlay, not routed on VPC) |
| Service CIDR | `10.241.0.0/16` (cluster-internal) |
| DNS Service IP | `10.241.0.10` |

Cross-cluster communication uses Cilium ClusterMesh, not L3 routing.

## Cost Considerations

| Resource | Cost | Notes |
|----------|------|-------|
| VPC, subnets, route tables, IGW | Free | — |
| NAT Gateway | ~$32/month each | Use `single_nat_gateway = true` for non-prod |
| S3 Gateway Endpoint | Free | Always created |
| VPC Flow Logs (CloudWatch) | ~$2-5/month | Depends on volume |
| VPC Flow Logs (S3) | ~$1-3/month | Cheaper for high-volume |

## Next Steps

Continue to [Kubernetes Network Design](08-kubernetes-network-design.md) for Kubernetes-specific networking details.
