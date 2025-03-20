# Azure AKS Core Module - West US (Dev)

## Overview
This module provisions and configures the core Azure Kubernetes Service (AKS) cluster in the West US region for the development environment. It sets up a production-ready Kubernetes platform with appropriate security and networking configurations.

## Configuration Details

### Purpose
Creates a production-ready AKS cluster that:
- Provides a secure platform for container workloads
- Follows Azure and Kubernetes best practices
- Implements private networking and enhanced security
- Enables proper monitoring and management

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group
- **network**: Uses network configuration for cluster networking
- **aks_identity**: Uses managed identity for the AKS cluster

### Key Configuration Settings
- **Cluster Configuration**:
  - Kubernetes Version: Latest stable version
  - Private Cluster: Enabled
  - Network Plugin: Azure CNI
  - Network Policy: Azure
  - Outbound Type: User-defined routing
- **System Node Pool**:
  - VM Size: Standard_D2s_v3
  - Node Count: 1-3 (Auto-scaling enabled)
  - Zone Redundancy: Enabled across 3 availability zones
  - OS Disk Size: 128 GB
  - Max Pods per Node: 30
- **Security Features**:
  - Microsoft Defender: Enabled
  - Azure Policy: Enabled
  - RBAC: Enabled
  - Local accounts: Disabled
  - Azure AD integration: Enabled
- **Monitoring**:
  - Azure Monitor: Enabled
  - Log Analytics Integration: Enabled

## Usage Example

To apply this module:
```bash
cd aks_core
terragrunt apply
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- aks_node_pools 