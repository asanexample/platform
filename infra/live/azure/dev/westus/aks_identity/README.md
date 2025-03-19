# Azure AKS Identity Terragrunt Configuration

This directory contains the Terragrunt configuration for deploying Azure Kubernetes Service (AKS) identities in the West US region. The AKS identity module creates and manages user-assigned managed identities for AKS clusters.

## Configuration Overview

The AKS identity is configured with:

- User-assigned managed identity for the AKS cluster
- RBAC role assignments for AKS operations
- Workload identity federation capability disabled (can be enabled when needed)

## Naming Attributes

The configuration uses the correct attribute from the naming module:

```hcl
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
    aks_identity = "mock-identity"  # Correct attribute name
  }
}

inputs = {
  # Identity naming
  aks_identity_name = dependency.naming.outputs.aks_identity  # Correct attribute reference
}
```

### Previous Issue (Now Fixed)

There was a previous issue where the configuration incorrectly referenced `user_assigned_identity` and `user_managed_identity` attributes, which don't exist in the naming module outputs:

```hcl
# Incorrect (old code):
mock_outputs = {
  aks_cluster = "mock-aks"
  user_assigned_identity = "mock-identity"  # This attribute doesn't exist
}

inputs = {
  aks_identity_name = dependency.naming.outputs.user_assigned_identity  # Incorrect reference
}
```

The fix ensures that the module correctly references `aks_identity` from the naming module, which is the proper attribute name for AKS identity resources.

## Dependencies

This module has dependencies on:

- **naming**: For standardized resource naming
- **resource_group**: For the resource group where the identity is deployed

## Applying Changes

To apply changes to the AKS identity configuration:

```bash
cd infra/live/azure/dev/westus/aks_identity
terragrunt plan
terragrunt apply
```

## Outputs

After deployment, the following outputs are available:

- **aks_identity_id**: The full resource ID of the user-assigned identity
- **aks_identity_client_id**: The client ID of the user-assigned identity
- **aks_identity_principal_id**: The principal ID of the user-assigned identity 