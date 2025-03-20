# Azure AKS Identity Module - West US (Dev)

## Overview
This module provisions and configures managed identities for Azure Kubernetes Service (AKS) in the West US region for the development environment. It creates and configures the necessary identities for AKS clusters and workloads.

## Configuration Details

### Purpose
Creates managed identities that:
- Enable secure authentication between AKS and other Azure services
- Support workload identity federation for Kubernetes applications
- Implement proper RBAC and least privilege access
- Eliminate the need for service principals with credentials

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group

### Key Configuration Settings
- **Cluster Identity**:
  - Type: User-assigned managed identity
  - Permissions: Network Contributor, Managed Identity Operator
- **Kubelet Identity**:
  - Type: User-assigned managed identity
  - Permissions: AcrPull
- **Workload Identities**:
  - Federated identity credential enabled
  - OIDC issuer profile configuration

### Role Assignments
- Network permissions for VNet and subnet management
- Container Registry pull permissions
- Managed Identity operator permissions for managing other identities

## Usage Example

To apply this module:
```bash
cd aks_identity
terragrunt apply
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- aks_core 