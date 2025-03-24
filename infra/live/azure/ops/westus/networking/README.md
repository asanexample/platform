# Azure Networking Module - East US (Dev)

## Overview
This module provisions Azure networking infrastructure including Virtual Networks, subnets, and network security groups for the East US region. It follows a multi-availability zone design with specifically allocated CIDR ranges.

## Configuration Details

### Purpose
Creates a complete networking foundation that:
- Implements a secure network topology
- Provisions subnets for different workload types across availability zones
- Configures appropriate service endpoints for Azure services
- Sets up networking for AKS private clusters

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group

### Network Architecture
- **VNet CIDR**: 10.0.0.0/16 (East US region allocation)
- **Subnets**:
  - **Node Subnets**:
    - az1-nodes: 10.0.0.0/24
    - az2-nodes: 10.0.10.0/24
    - az3-nodes: 10.0.20.0/24
  - **Shared Subnets**:
    - endpoints: 10.0.30.0/24
    - firewall: 10.0.31.0/26 (For Azure Firewall)
    - bastion: 10.0.31.64/26 (For Azure Bastion)
    - gateway: 10.0.31.128/26 (For VPN Gateway)

### Key Configuration Settings
- **Network Security Groups**:
  - Node subnet NSGs configured for AKS traffic
  - Endpoint subnet NSGs allow Azure services traffic
  - Custom security rules for specific workloads
- **Private Endpoints**:
  - Dedicated subnet for Azure Private Endpoints
  - Private DNS zones for private endpoint resolution
- **Service Endpoints**:
  - Storage, Key Vault, Container Registry, and SQL
  - Enhanced security through direct service connectivity
- **Private Cluster Support**:
  - Private DNS zone for AKS private cluster (privatelink.eastus.azmk8s.io)
  - Private endpoint network policies

## Network Security Approach
- **Micro-segmentation**: Each node pool in a dedicated subnet
- **Zero Trust**: Default deny with explicit allow rules
- **Defense in Depth**: Multiple security layers (NSGs, private endpoints, service endpoints)
- **East-West Traffic**: Allowed between node subnets for cluster communication
- **North-South Traffic**: Controlled through load balancers and/or firewall rules

## Implementation Details
The networking module uses the [Azure Networking Module](/infra/modules/azure/networking) to create a comprehensive network foundation with zone-specific subnets. This design:

- Improves fault isolation by aligning subnets with availability zones
- Enables granular network security controls per subnet
- Allows for future expansion with predictable CIDR allocations
- Supports integration with hub-spoke topologies

## Usage Example

To apply this module:
```bash
cd networking
terragrunt apply
```

To view the network structure after deployment:
```bash
cd networking
terragrunt output subnet_ids
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- key_vault
- storage
- aks_core
- aks_node_pools
- container_registry 