# Azure Networking Module - West US (Dev)

## Overview
This module provisions Azure networking infrastructure including Virtual Networks, subnets, and network security groups for the West US region. It follows a multi-availability zone design with specifically allocated CIDR ranges.

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
- **VNet CIDR**: 10.101.24.0/21 (West US region allocation)
- **Subnets**:
  - **AZ1 Subnets**:
    - Kubernetes: 10.101.24.0/26
    - Services: 10.101.24.64/27
    - Endpoints: 10.101.24.96/28
    - Transit: 10.101.24.112/29
  - **AZ2 Subnets**:
    - Kubernetes: 10.101.25.0/26
    - Services: 10.101.25.64/27
    - Endpoints: 10.101.25.96/28
    - Transit: 10.101.25.112/29
  - **AZ3 Subnets**:
    - Kubernetes: 10.101.26.0/26
    - Services: 10.101.26.64/27
    - Endpoints: 10.101.26.96/28
    - Transit: 10.101.26.112/29

### Key Configuration Settings
- AKS networking enabled for private clusters
- Service endpoints configured for Storage, Key Vault, and other services
- Network security groups with appropriate rules

## Usage Example

To apply this module:
```bash
cd networking
terragrunt apply
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- key_vault
- storage
- aks_core
- aks_node_pools 