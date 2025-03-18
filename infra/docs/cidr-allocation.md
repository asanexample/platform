# Hierarchical CIDR Allocation Strategy [DEPRECATED]

> **IMPORTANT: This document is deprecated.** Please refer to the current network topology documentation at [network-topology.md](./network-topology.md).

This document outlines our previous hierarchical CIDR allocation strategy for multi-cloud environments. The strategy combines hierarchical CIDR allocation for clear organizational boundaries with Kubernetes-optimized subnet designs for operational efficiency.

## Global Address Space Hierarchy

We use a hierarchical CIDR allocation approach to organize our address space:

```
10.0.0.0/8 (Organization-wide address space)
│
├── 10.0.0.0/12 - AWS Infrastructure
│
├── 10.16.0.0/12 - Azure Infrastructure
│   │
│   ├── 10.16.0.0/16 - Azure Management/Hub
│   │
│   ├── 10.17.0.0/16 - Azure Dev Environment
│   │   │
│   │   ├── 10.17.0.0/23 - Azure Dev East US
│   │   │   ├── 10.17.0.0/25 - AZ1
│   │   │   ├── 10.17.0.128/25 - AZ2
│   │   │   └── 10.17.1.0/25 - AZ3
│   │   │
│   │   └── 10.17.2.0/23 - Azure Dev West US
│   │       ├── 10.17.2.0/25 - AZ1
│   │       ├── 10.17.2.128/25 - AZ2
│   │       └── 10.17.3.0/25 - AZ3
│   │
│   ├── 10.18.0.0/16 - Azure Test Environment (Reserved)
│   │
│   └── 10.19.0.0/16 - Azure Production Environment (Reserved)
│
└── 10.32.0.0/12 - GCP Infrastructure (Reserved)
```

## Allocation Benefits

1. **Visual IP Recognition**: IPs can instantly be identified by environment
   - 10.17.x.x = Azure Dev
   - 10.19.x.x = Azure Prod (future)

2. **Simplified Security Rules**: Broad security rules can use environment boundaries 
   - Example: `allow from 10.16.0.0/16 to 10.17.0.0/16 port 443`

3. **Future-Proofing**: Structure accommodates:
   - Additional environments (staging, QA)
   - New cloud providers
   - New regions within existing environments

## Kubernetes Network Design

Within each region, we follow a 3-AZ Kubernetes-optimized design:

1. **Each Availability Zone (AZ) gets a /25 CIDR block**
2. **Each AZ has specialized subnet types**:
   - **Node Subnets** (/26): For Kubernetes worker nodes (62 IPs per AZ)
   - **Load Balancer Subnets** (/28): For load balancers (14 IPs per AZ)
   - **Endpoint Subnets** (/28): For private endpoints and service connections (14 IPs per AZ)
   - **Transit Subnets** (/29): For transit gateways or routing (6 IPs per AZ)
3. **Reserved space** in each AZ for future expansion

## Current Allocations

| Environment | Region | CIDR Range      | Usage                  |
|-------------|--------|-----------------|------------------------|
| Dev         | EastUS | 10.17.0.0/23    | Azure Dev EastUS VNet  |
| Dev         | WestUS | 10.17.2.0/23    | Azure Dev WestUS VNet  |

## Reserved Allocations

| Environment | Region | CIDR Range      | Status                 |
|-------------|--------|-----------------|------------------------|
| Dev         | EastUS | 10.17.1.128/25  | Reserved for expansion |
| Dev         | WestUS | 10.17.3.128/25  | Reserved for expansion |
| Test        | Global | 10.18.0.0/16    | Reserved for future    |
| Prod        | Global | 10.19.0.0/16    | Reserved for future    |
| All         | GCP    | 10.32.0.0/12    | Reserved for future    |

## Implementation Notes

1. All network ACLs, security groups, and firewall rules should leverage the hierarchical structure wherever possible
2. As new environments or regions are added, they should follow this allocation pattern
3. When creating Kubernetes clusters, use CNIs like Cilium that create their own private pod networks
4. Pod and service CIDR blocks should not overlap with our VPC CIDR ranges:
   - Recommended Pod CIDR: 172.16.0.0/16
   - Recommended Service CIDR: 172.17.0.0/16

## Governance

This document should be reviewed before any new network allocation and updated as allocations change. All networking infrastructure-as-code should reference this document for CIDR allocation. 