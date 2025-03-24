# Azure AKS Identity Module - East US (Dev)

## Overview
This module provisions and configures managed identities for Azure Kubernetes Service (AKS) in the East US region for the development environment. It creates and configures the necessary identities for AKS clusters and workloads.

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
  - Permissions: Network Contributor, Managed Identity Operator, DNS Zone Contributor
- **Kubelet Identity**:
  - Type: User-assigned managed identity
  - Permissions: AcrPull, Storage Blob Data Reader
- **Workload Identities**:
  - Federation enabled via OIDC issuer
  - Support for Azure AD Pod Identity replacement

### Role Assignments
The following role assignments are created:
- **Networking Permissions**:
  - Network Contributor on the VNet resource
  - Private DNS Zone Contributor for AKS private cluster zones
- **Data Access Permissions**:
  - AcrPull on container registries 
  - Storage Blob Data Reader on specific storage accounts
- **Identity Management**:
  - Managed Identity Operator for identity management tasks

## Workload Identity Integration
This module configures the foundation for Azure Workload Identity, which enables:

1. **Pod-to-Azure Authentication**: Kubernetes service accounts can be mapped to Azure managed identities
2. **Federation**: Using OIDC tokens rather than shared secrets or keys
3. **Fine-grained Access Control**: Each application can have its own identity with minimal permissions

## Implementation Details
The module leverages user-assigned managed identities rather than system-assigned identities to enable:
- Separation of identity lifecycle from the resource lifecycle
- Pre-creation of identities before AKS cluster deployment
- Pre-configuration of role assignments
- Multiple AKS clusters sharing the same identity if needed

## Usage Example

To apply this module:
```bash
cd aks_identity
terragrunt apply
```

To view the created identities:
```bash
cd aks_identity
terragrunt output identities
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- aks_core 