# Azure AKS Node Pools Module - East US (Dev)

## Overview
This module provisions and configures additional node pools for Azure Kubernetes Service (AKS) in the East US region for the development environment. It creates specialized node pools for different workload types.

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
- **networking**: Uses subnet configuration for node pool network isolation

### Key Configuration Settings
- **Application Node Pool**:
  - VM Size: Standard_D8s_v3
  - Mode: User
  - Node Count: 3-10 (Auto-scaling enabled)
  - Zone Redundancy: Enabled across 3 availability zones
  - OS Disk Type: Ephemeral
  - OS Disk Size: 128 GB
  - Max Pods per Node: 50
  - Node Labels: role=app
  - Node Taints: None
  - Subnet: az2-nodes
- **Monitoring Node Pool**:
  - VM Size: Standard_D4s_v3
  - Mode: User
  - Node Count: 2-4 (Auto-scaling enabled)
  - Zone Redundancy: Enabled across 3 availability zones
  - OS Disk Type: Managed
  - OS Disk Size: 128 GB
  - Max Pods per Node: 30
  - Node Labels: role=monitoring
  - Node Taints: role=monitoring:NoSchedule
  - Subnet: az3-nodes

## Network Design
Each node pool is placed in a dedicated subnet to enable:
- Better network isolation
- Independent scaling without IP address constraints
- Subnet-level network security groups for additional security
- Zone-specific subnets for increased failure domain isolation

## Implementation Details
This module builds on the core AKS cluster by adding specialized node pools for:

1. **Application Workloads**:
   - Optimized for general application containers
   - Higher resource allocation for production workloads
   - Auto-scaling based on actual resource usage

2. **Monitoring Infrastructure**:
   - Dedicated resources for monitoring components
   - Isolated from application workloads via taints
   - Properly sized for Prometheus, Grafana, and logging components

## Usage Example

To apply this module:
```bash
cd aks_node_pools
terragrunt apply
```

## Workload Placement
Applications can target specific node pools using Kubernetes concepts:
- **Node Selectors**: `nodeSelector: { role: app }`
- **Node Affinity**: For more complex scheduling rules
- **Tolerations**: Required for scheduling on tainted nodes (e.g., monitoring nodes)

Example:
```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: example-app
spec:
  template:
    spec:
      nodeSelector:
        role: app
```

## Dependencies on this Module
No other modules depend on this module as it's typically one of the final components in the deployment sequence. 