# Network Topology

## Overview

The VIP Platform implements a comprehensive network topology that spans multiple cloud providers, regions, and environments. This document describes the network architecture, connectivity patterns, and security boundaries implemented in the platform.

The current implementation focuses on Azure, with AWS and GCP planned for future phases. The architecture follows a hierarchical CIDR allocation strategy that ensures clear network boundaries and proper isolation between different segments of the infrastructure.

## Design Principles

The network topology is designed according to the following principles:

1. **Multi-Cloud Connectivity**: Seamless connectivity across AWS, Azure, and GCP.
2. **Multi-Region Support**: Support for resources distributed across multiple geographic regions.
3. **Security by Default**: Default-deny approach with explicit permissions only where needed.
4. **Availability Zone Awareness**: Resources distributed across multiple availability zones for high availability.
5. **Service Segmentation**: Network segmentation for different service types and security requirements.

## Network Components

### Virtual Networks / VPCs

In each cloud provider, separate virtual networks (VNets in Azure, VPCs in AWS/GCP) are created for different environments:

- Development VNet/VPC
- Testing VNet/VPC (planned)
- Production VNet/VPC (planned)

Each virtual network is allocated a distinct CIDR range according to our hierarchical allocation strategy. For Azure, this follows the pattern:

| Environment | CIDR Range | Implementation Status |
|-------------|------------|----------------------|
| Development | 10.104.0.0/16 | Implemented (eastus) |
| Testing | 10.200.64.0/18 | Planned |
| Production | 10.200.128.0/18 | Planned |

### Subnets

Each VNet/VPC contains specialized subnets distributed across availability zones. The platform uses a consistent subnet structure across all regions and environments:

#### Kubernetes Node Subnets
- **Purpose**: Host AKS worker nodes
- **Size**: /26 (62 usable IPs per AZ)
- **Example**: 10.104.0.0/26 (AZ1), 10.104.1.0/26 (AZ2), 10.104.2.0/26 (AZ3)
- **Service Endpoints**: Storage, KeyVault, ContainerRegistry
- **Security**: NSGs with AKS-specific rules

#### Service Subnets
- **Purpose**: Host databases and other cloud resources requiring IP addresses
- **Size**: /27 (30 usable IPs per AZ)
- **Example**: 10.104.0.64/27 (AZ1), 10.104.1.64/27 (AZ2), 10.104.2.64/27 (AZ3)
- **Service Endpoints**: Storage, KeyVault, SQL
- **Security**: Controlled ingress/egress with appropriate NSGs

#### Endpoint Subnets
- **Purpose**: Host private endpoints for PaaS services
- **Size**: /28 (14 usable IPs per AZ)
- **Example**: 10.104.0.96/28 (AZ1), 10.104.1.96/28 (AZ2), 10.104.2.96/28 (AZ3)
- **Service Endpoints**: Storage, SQL, KeyVault
- **Security**: Highly restricted access with tight NSG rules

#### Transit Subnets
- **Purpose**: Enable connectivity between different network segments
- **Size**: /29 (6 usable IPs per AZ)
- **Example**: 10.104.0.128/29 (AZ1), 10.104.1.128/29 (AZ2), 10.104.2.128/29 (AZ3)
- **Service Endpoints**: Storage
- **Security**: Tightly controlled routing and security rules

#### Public Subnets
- **Purpose**: Host load balancers and other public-facing resources
- **Size**: /28 (14 usable IPs per AZ)
- **Example**: 10.104.0.112/28 (AZ1), 10.104.1.112/28 (AZ2), 10.104.2.112/28 (AZ3)
- **Service Endpoints**: Storage
- **Security**: Public-facing but with strict NSG rules

### Security Controls

The network topology implements several security controls:

1. **Network Security Groups (NSGs)**: Every subnet has an associated NSG that controls inbound and outbound traffic.
   - AKS-specific NSGs include rules to allow Azure Load Balancer traffic and deny all other inbound traffic by default.
   - Service-specific NSGs implement least-privilege access rules.

2. **Service Endpoints**: Subnets leverage Azure Service Endpoints to secure connectivity to PaaS services:
   - Storage service endpoints on all subnets
   - KeyVault endpoints on Kubernetes, Services, and Endpoints subnets
   - SQL endpoints on Services and Endpoints subnets
   - ContainerRegistry endpoints on Kubernetes subnets

3. **Private Endpoints**: Dedicated Endpoint subnets in each AZ host private endpoints to Azure services, removing exposure to the public internet.

4. **Default Deny**: All NSGs follow a default-deny approach with explicit allow rules only for required traffic.

### Connectivity

The VIP Platform implements a hub-and-spoke networking model:

- **Regional Hub VNets**: Planned for centralized connectivity and security services
- **Spoke VNets**: Current implementation with environment-specific resources
- **VNet Peering**: Used for connectivity between VNets within a region
- **Private DNS Zones**: For name resolution of private endpoints and private AKS clusters
- **Azure Private Link**: For secure connectivity to PaaS services

For AKS clusters, the platform supports:
- **Private Clusters**: API servers accessible only from within the VNet
- **Private DNS Zones**: Automatically created for AKS private clusters (privatelink.{region}.azmk8s.io)
- **AKS Egress Control**: Support for both outbound NAT and user-defined routing
- **Load Balancers**: Hosted in public subnets for external access to services

## Kubernetes Network Integration

Kubernetes clusters are deployed with the following network configurations:

1. **Network Plugin**: Cilium CNI for enhanced security and networking capabilities
2. **Pod/Service CIDRs**:
   - Pod CIDR: 10.240.0.0/16
   - Service CIDR: 10.241.0.0/16
   - DNS Service IP: 10.241.0.10

3. **Multi-AZ Deployment**: AKS clusters span multiple availability zones with node pools distributed across dedicated subnets in each AZ.

4. **Network Policies**: Support for Cilium Network Policies providing advanced security features, traffic visibility, and enhanced performance through eBPF.

## Implementation Status

The current network topology implementation includes:
- Azure Development environment in East US region
- Three availability zones with the full subnet structure in each AZ
- NSGs and service endpoints for all subnets
- AKS-specific network configurations with multi-AZ support

Future phases will extend the implementation to:
- Additional Azure regions
- Production and testing environments
- AWS and GCP cloud providers
- Hub-and-spoke connectivity with global transit options

## Next Steps

Continue to [Kubernetes Network Design](08-kubernetes-network-design.md) to understand how Kubernetes networking is implemented within this network topology. 