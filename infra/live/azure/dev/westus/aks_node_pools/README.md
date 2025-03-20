# Azure AKS Node Pools Module - West US (Dev)

## Overview
This module provisions and configures additional node pools for Azure Kubernetes Service (AKS) in the West US region for the development environment. It creates specialized node pools for different workload types.

## Configuration Details

### Purpose
Creates specialized AKS node pools that:
- Provide dedicated resources for different workload types
- Implement appropriate scaling and sizing for each workload
- Enable workload isolation and optimization
- Support high availability across availability zones

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group
- **aks_core**: References the core AKS cluster

### Key Configuration Settings
- **Application Node Pool**:
  - VM Size: Standard_D4s_v3
  - Mode: User
  - Node Count: 1-5 (Auto-scaling enabled)
  - Zone Redundancy: Enabled across 3 availability zones
  - OS Disk Size: 128 GB
  - Max Pods per Node: 30
  - Node Labels: workload-type=application
  - Node Taints: None
- **Utility Node Pool**:
  - VM Size: Standard_D2s_v3
  - Mode: User
  - Node Count: 1-3 (Auto-scaling enabled)
  - Zone Redundancy: Enabled
  - Node Labels: workload-type=utility
  - Node Taints: utility=true:NoSchedule

## Usage Example

To apply this module:
```bash
cd aks_node_pools
terragrunt apply
```

## Dependencies on this Module
No other modules depend on this module as it's typically one of the final components in the deployment sequence. 