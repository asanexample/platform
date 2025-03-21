# CIDR Allocation Strategy

## Overview

The VIP Platform uses a hierarchical CIDR allocation strategy to organize IP address spaces across multiple cloud providers, regions, and environments. This approach ensures clear network boundaries, non-overlapping address spaces, and proper isolation between different network segments.

## Hierarchical Allocation Principles

The CIDR allocation follows a hierarchical structure with the following levels:

```mermaid
graph TD
    subgraph "CIDR Allocation Hierarchy"
    A[Top-Level Address Space] --> B[Cloud Provider Level]
    B --> C[Environment Level]
    C --> D[Region Level]
    D --> E[Availability Zone Level]
    E --> F[Subnet Level]
    
    classDef default fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef level0 fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef level1 fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef level2 fill:#fff8e1,stroke:#ff8f00,stroke-width:2px;
    classDef level3 fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;
    classDef level4 fill:#ffebee,stroke:#c62828,stroke-width:2px;
    
    class A level0;
    class B level1;
    class C level2;
    class D level3;
    class E level4;
    class F level4;
    end
```

1. **Cloud Provider Level**: Distinct address blocks allocated for each cloud provider
2. **Environment Level**: Subdivision for different environments (dev, test, prod)
3. **Region Level**: Further subdivision for specific geographic regions
4. **Availability Zone Level**: Dedicated address spaces for each availability zone
5. **Subnet Level**: Specialized subnets within each availability zone

This hierarchy provides clear organizational boundaries and simplifies network planning and troubleshooting.

## Address Space Allocation

### Top-Level Allocation

The top-level address allocations for cloud providers are:

| Cloud Provider | CIDR Range | Implementation Status |
|----------------|------------|----------------------|
| AWS | 10.100.0.0/16 | Planned |
| Azure | 10.200.0.0/16 | Implemented |
| GCP | 10.300.0.0/16 | Planned |

### Environment Allocation

Within each cloud provider, environments are allocated specific ranges:

| Cloud Provider | Environment | CIDR Range | Implementation Status |
|----------------|-------------|------------|----------------------|
| Azure | Development | 10.200.0.0/18 | Implemented |
| Azure | Testing | 10.200.64.0/18 | Planned |
| Azure | Production | 10.200.128.0/18 | Planned |
| AWS | Development | 10.100.0.0/18 | Planned |
| AWS | Testing | 10.100.64.0/18 | Planned |
| AWS | Production | 10.100.128.0/18 | Planned |
| GCP | Development | 10.300.0.0/18 | Planned |
| GCP | Testing | 10.300.64.0/18 | Planned |
| GCP | Production | 10.300.128.0/18 | Planned |

### Region Allocation

Each region within an environment receives a specific CIDR block:

| Environment | Region | CIDR Range | Implementation Status |
|-------------|--------|------------|----------------------|
| Azure Dev | East US | 10.200.0.0/21 | Implemented |
| Azure Dev | West US | 10.200.8.0/21 | Planned |
| Azure Dev | North Europe | 10.200.16.0/21 | Planned |
| AWS Dev | us-east-1 | 10.100.0.0/21 | Planned |
| AWS Dev | us-west-2 | 10.100.8.0/21 | Planned |
| AWS Dev | eu-west-1 | 10.100.16.0/21 | Planned |

### Availability Zone Allocation

Within each region, each availability zone gets a dedicated address space:

| Region | Availability Zone | CIDR Range | Implementation Status |
|--------|-------------------|------------|----------------------|
| East US | Zone 1 | 10.200.0.0/24 | Implemented |
| East US | Zone 2 | 10.200.1.0/24 | Implemented |
| East US | Zone 3 | 10.200.2.0/24 | Implemented |
| West US | Zone 1 | 10.200.8.0/24 | Planned |
| West US | Zone 2 | 10.200.9.0/24 | Planned |
| West US | Zone 3 | 10.200.10.0/24 | Planned |

### Subnet Allocation

Each availability zone contains specialized subnets for different purposes:

| AZ | Subnet Type | CIDR Range | Size | Purpose | Implementation Status |
|----|-------------|------------|------|---------|----------------------|
| Zone 1 | Node | 10.200.0.0/26 | /26 (62 IPs) | Kubernetes worker nodes | Implemented |
| Zone 1 | Services | 10.200.0.64/27 | /27 (30 IPs) | Load balancers and service endpoints | Implemented |
| Zone 1 | Endpoints | 10.200.0.96/28 | /28 (14 IPs) | Private service endpoints | Implemented |
| Zone 1 | Transit | 10.200.0.112/29 | /29 (6 IPs) | Transit connectivity | Implemented |
| Zone 2 | Node | 10.200.1.0/26 | /26 (62 IPs) | Kubernetes worker nodes | Implemented |
| Zone 2 | Services | 10.200.1.64/27 | /27 (30 IPs) | Load balancers and service endpoints | Implemented |
| Zone 2 | Endpoints | 10.200.1.96/28 | /28 (14 IPs) | Private service endpoints | Implemented |
| Zone 2 | Transit | 10.200.1.112/29 | /29 (6 IPs) | Transit connectivity | Implemented |

## Subnet Types and Purposes

The VIP Platform uses specialized subnet types for different infrastructure components:

### Node Subnets

Node subnets host Kubernetes worker nodes and related infrastructure:

- Size: /26 (62 usable IPs)
- Purpose: AKS/EKS/GKE worker nodes
- Security: Restricted access from other subnets
- Configuration: NSGs/Security Groups with specific Kubernetes rules

### Services Subnets

Services subnets host load balancers and service endpoints:

- Size: /27 (30 usable IPs)
- Purpose: Load balancers, NAT gateways
- Security: Controlled ingress/egress
- Configuration: Appropriate rules for service traffic

### Endpoints Subnets

Endpoints subnets contain private endpoints for secure service access:

- Size: /28 (14 usable IPs)
- Purpose: Private endpoints for PaaS services
- Security: Highly restricted access
- Configuration: Limited traffic to specific services

### Transit Subnets

Transit subnets enable connectivity between different network segments:

- Size: /29 (6 usable IPs)
- Purpose: VPN, ExpressRoute, Transit Gateway connections
- Security: Tightly controlled routing
- Configuration: Specific route tables and security rules

## Implementation in Terraform

The CIDR allocation strategy is implemented in Terraform using structured variable definitions:

```hcl
locals {
  # Region CIDR blocks
  region_cidrs = {
    eastus = "10.200.0.0/21"
    westus = "10.200.8.0/21"
  }
  
  # AZ CIDR blocks for East US
  eastus_az_cidrs = {
    "1" = "10.200.0.0/24"
    "2" = "10.200.1.0/24"
    "3" = "10.200.2.0/24"
  }
  
  # Subnet allocations for each AZ
  subnet_cidrs = {
    node      = cidrsubnet(local.eastus_az_cidrs["1"], 2, 0) # 10.200.0.0/26
    services  = cidrsubnet(local.eastus_az_cidrs["1"], 3, 2) # 10.200.0.64/27
    endpoints = cidrsubnet(local.eastus_az_cidrs["1"], 4, 6) # 10.200.0.96/28
    transit   = cidrsubnet(local.eastus_az_cidrs["1"], 5, 14) # 10.200.0.112/29
  }
}
```

In the current implementation, these CIDR configurations are specified in the `network.hcl` file in the region directory (e.g., `infra/live/azure/dev/eastus/network.hcl`).

## Allocation File

The platform maintains a comprehensive CSV file (`allocations.csv`) that documents all CIDR allocations across all cloud providers, environments, regions, and availability zones. This file serves as the source of truth for network planning and is used to:

1. Document all allocated address spaces
2. Prevent IP range overlaps
3. Plan future network expansions
4. Provide reference for troubleshooting

The file contains the following information:

- Account/Subscription name
- VPC/VNet name
- Cloud provider
- Region
- Availability zone
- CIDR ranges at all hierarchy levels
- Subnet purpose
- Number of available IPs

## Benefits of Hierarchical CIDR Allocation

This allocation strategy provides several key benefits:

1. **Clear Boundaries**: Each segment of the infrastructure has well-defined network boundaries
2. **Simplified Troubleshooting**: Easy to identify the location of an IP address in the hierarchy
3. **Consistent Sizing**: Standardized subnet sizes based on purpose and requirements
4. **Future Expansion**: Reserved space for additional regions and environments
5. **Avoid Overlaps**: Prevents IP conflicts when connecting networks
6. **Simplified Routing**: Hierarchical aggregation allows for route summarization

## Kubernetes Network Design Considerations

The CIDR allocation strategy is specifically optimized for Kubernetes deployments with:

1. **Pod CIDR Ranges**: Separate from infrastructure CIDRs to avoid conflicts
2. **Service CIDR Ranges**: Non-overlapping with infrastructure and pod CIDRs
3. **Node Density Planning**: Subnet sizes accommodate expected node count
4. **Multi-AZ Design**: Pods distributed across multiple availability zones

See [Kubernetes Network Design](08-kubernetes-network-design.md) for more details on the Kubernetes-specific network configurations.

## Current Implementation Status

The CIDR allocation strategy is currently implemented for:
- Azure Development environment in East US region
- AKS clusters with node pools in multiple availability zones

Future phases will extend the implementation to:
- Additional Azure regions
- Production and testing environments
- AWS and GCP cloud providers

## Next Steps

Continue to [Network Topology](07-network-topology.md) to understand how the CIDR allocation strategy is applied to the overall network architecture of the VIP Platform. 