# Network Topology

This document describes the network topology used in the multi-cloud platform, including design patterns, connectivity models, and security controls.

## Overview

Our network architecture follows a hierarchical design optimized for Kubernetes workloads, with multi-AZ deployment in each region for high availability. The design emphasizes security, isolation, and scalability.

## Core Network Design Principles

1. **Hierarchical Address Space**: Clear CIDR hierarchy following our [CIDR Allocation Strategy](cidr-allocation.md)
2. **Default Deny**: All network traffic is denied by default, with explicit allow rules
3. **Defense in Depth**: Multiple security layers at network, subnet, and resource levels
4. **Availability Zone Awareness**: Resources distributed across 3 AZs for high availability
5. **Service Isolation**: Separate subnets for different service types
6. **Private Access**: Private endpoints for Azure PaaS services

## Azure Network Architecture

### Virtual Network Design

Each region in each environment has its own dedicated virtual network with the following components:

```
Virtual Network (10.x.0.0/16)
├── Availability Zone 1 (10.x.0.0/18)
│   ├── AKS Node Subnet (10.x.0.0/20)
│   ├── AKS Pod Subnet (10.x.16.0/20)
│   └── Private Endpoint Subnet (10.x.32.0/24)
├── Availability Zone 2 (10.x.64.0/18)
│   ├── AKS Node Subnet (10.x.64.0/20)
│   ├── AKS Pod Subnet (10.x.80.0/20)
│   └── Private Endpoint Subnet (10.x.96.0/24)
├── Availability Zone 3 (10.x.128.0/18)
│   ├── AKS Node Subnet (10.x.128.0/20)
│   ├── AKS Pod Subnet (10.x.144.0/20)
│   └── Private Endpoint Subnet (10.x.160.0/24)
└── Shared Services (10.x.192.0/18)
    ├── Gateway Subnet (10.x.192.0/24)
    ├── Firewall Subnet (10.x.193.0/24)
    ├── Bastion Subnet (10.x.194.0/24)
    └── Management Subnet (10.x.195.0/24)
```

### Network Security Groups

Each subnet has a dedicated NSG with appropriate security rules:

| Subnet Type | Inbound Rules | Outbound Rules |
|-------------|---------------|----------------|
| AKS Node | Allow from Azure Load Balancer<br>Allow from AKS control plane<br>Allow from other node subnets | Allow to Internet<br>Allow to other node subnets<br>Allow to pod subnets |
| AKS Pod | Allow from node subnets<br>Allow from other pod subnets | Allow to Internet<br>Allow to node subnets<br>Allow to other pod subnets |
| Private Endpoint | Allow from VNET | Deny all |
| Gateway | Allow HTTPS/443 from Internet | Allow to VNet |
| Bastion | Allow HTTPS/443 from Internet<br>Allow SSH/22 from Internet | Allow to VNet |
| Management | Allow from Bastion | Allow to Internet |

### Service Endpoints

The following Azure service endpoints are enabled on appropriate subnets:

| Subnet | Service Endpoints |
|--------|-------------------|
| AKS Node | Microsoft.Storage<br>Microsoft.KeyVault<br>Microsoft.ContainerRegistry |
| AKS Pod | Microsoft.Storage<br>Microsoft.KeyVault<br>Microsoft.ContainerRegistry |
| Private Endpoint | None |
| Management | Microsoft.Storage<br>Microsoft.KeyVault |

### Private Endpoints

Private endpoints are used for secure access to the following PaaS services:

1. Storage Accounts
2. Key Vaults
3. Container Registries
4. Azure SQL Databases

Each private endpoint is deployed in its respective AZ's Private Endpoint subnet and has its own private IP address within the VNET.

## Multi-Region Connectivity

For environments requiring multi-region connectivity, Global VNet Peering is used to connect VNets across regions:

```
           ┌─────────────────┐         ┌─────────────────┐
           │  East US VNet   │◄───────►│  West US VNet   │
           └─────────────────┘         └─────────────────┘
                    ▲                          ▲
                    │                          │
                    ▼                          ▼
           ┌─────────────────┐         ┌─────────────────┐
           │ East US Private │         │ West US Private │
           │    Endpoints    │         │    Endpoints    │
           └─────────────────┘         └─────────────────┘
```

## Kubernetes Network Integration

### Azure CNI Networking

AKS clusters use Azure CNI networking with the following configuration:

1. **Pod Subnets**: Dedicated subnets for pod IP addresses
2. **Network Policy**: Calico network policy enabled for pod-to-pod traffic control
3. **Standard Load Balancer**: Used for Kubernetes services
4. **Internal Load Balancers**: For internal services (not exposed to internet)
5. **NAT Gateway**: For outbound traffic from nodes and pods

### Ingress Configuration

For ingress to Kubernetes applications:

1. **Internal Ingress**: NGINX Ingress Controllers with internal load balancers for apps that should only be accessible within the VNet
2. **External Ingress**: Azure Front Door for global load balancing and WAF protection

```
Internet
   │
   ▼
┌─────────────────┐
│  Azure Front    │
│     Door        │
└─────────────────┘
   │
   ▼
┌─────────────────┐
│  AKS Ingress    │
│  Controller     │
└─────────────────┘
   │
   ▼
┌─────────────────┐
│  Kubernetes     │
│  Services       │
└─────────────────┘
```

## Network Monitoring and Diagnostics

1. **Flow Logs**: NSG flow logs enabled and stored in Log Analytics
2. **Diagnostic Settings**: All network resources have diagnostic settings enabled
3. **Network Watcher**: Enabled for troubleshooting network issues
4. **Traffic Analytics**: Configured for network traffic patterns analysis

## Security Controls

### Network Layer Security

1. **NSGs**: Applied at subnet level with restrictive rules
2. **Service Endpoints**: Enable direct access to Azure services without going over public internet
3. **Private Endpoints**: For secure access to PaaS services
4. **DDoS Protection**: Standard DDoS protection enabled on VNets

### Application Layer Security

1. **Web Application Firewall**: Enabled on Front Door and Application Gateway
2. **TLS Termination**: TLS 1.2+ enforced at ingress points
3. **Network Policy**: Calico network policy for pod-to-pod traffic control

## Implementation in Terraform

The network topology is implemented through the following modules:

1. **Azure Networking Module**: Creates the VNet and subnet structure
2. **AKS Networking Module**: Configures AKS-specific networking components
3. **Private Endpoint Configurations**: In various resource modules (Storage, Key Vault, etc.)
4. **Front Door Module**: For global load balancing and WAF

Example Terraform configuration for the VNet structure:

```hcl
module "networking" {
  source = "../../modules/azure/networking"
  
  # Basic settings
  resource_group_name = "vip-rg-dev-eus-net"
  location            = "eastus"
  
  # Network settings
  vnet_name           = "vip-vnet-dev-eus-main"
  address_space       = ["10.8.0.0/16"]  # Dev East US
  
  # AZ1 Subnets
  az1_subnets = {
    nodes = {
      name             = "az1-node-subnet"
      address_prefixes = ["10.8.0.0/20"]
      service_endpoints = [
        "Microsoft.Storage",
        "Microsoft.KeyVault",
        "Microsoft.ContainerRegistry"
      ]
    }
    pods = {
      name             = "az1-pod-subnet"
      address_prefixes = ["10.8.16.0/20"]
      service_endpoints = [
        "Microsoft.Storage",
        "Microsoft.KeyVault",
        "Microsoft.ContainerRegistry"
      ]
    }
    endpoints = {
      name             = "az1-endpoint-subnet"
      address_prefixes = ["10.8.32.0/24"]
    }
  }
  
  # Similar configurations for AZ2 and AZ3
  # ...
  
  # Shared services subnets
  shared_subnets = {
    gateway = {
      name             = "gateway-subnet"
      address_prefixes = ["10.8.192.0/24"]
    }
    firewall = {
      name             = "firewall-subnet"
      address_prefixes = ["10.8.193.0/24"]
    }
    bastion = {
      name             = "bastion-subnet"
      address_prefixes = ["10.8.194.0/24"]
    }
    management = {
      name             = "management-subnet"
      address_prefixes = ["10.8.195.0/24"]
      service_endpoints = [
        "Microsoft.Storage",
        "Microsoft.KeyVault"
      ]
    }
  }
  
  # Tags
  tags = {
    Environment    = "dev"
    CIDRHierarchy  = "Azure-Dev-EastUS"
    NetworkDesign  = "Kubernetes3AZ"
  }
}
```

## Considerations for Multi-Cloud

When extending to other cloud providers, similar networking patterns are followed with cloud-specific implementations:

1. **AWS**: VPCs with subnets spread across multiple AZs
2. **GCP**: VPC networks with subnets in multiple zones
3. **Inter-cloud Connectivity**: Established via VPN or dedicated interconnects

## Change Management

Network changes follow strict change management procedures:

1. Plan changes in lower environments first
2. Document all changes to CIDR allocation
3. Test connectivity before and after changes
4. Implement changes during scheduled maintenance windows
5. Maintain backup of network configurations

## References

- [CIDR Allocation Strategy](cidr-allocation.md) - Network addressing strategy
- [Multi-Region Deployment](multi-region-deployment.md) - Guide for multi-region deployments 