# Azure AKS Identity Module

## Overview

This module creates and configures identities for Azure Kubernetes Service (AKS) clusters, implementing secure identity management and workload identity federation for authentication with Azure resources.

## Features

- Creates and manages user-assigned managed identities for AKS clusters
- Implements workload identity federation for secure pod authentication
- Configures federated identity credentials for Kubernetes service accounts
- Supports both system-assigned and user-assigned identity configurations
- Enables OIDC issuer integration for modern authentication patterns

## Usage

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  # Basic settings
  resource_group_name = "rg-aks-dev-eastus"
  location            = "eastus"
  
  # Identity settings
  identity_type       = "UserAssigned"
  user_assigned_identity_name = "id-aks-dev-eastus"
  
  # Workload Identity Federation settings
  enable_workload_identity = true
  
  # Tags
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
    Component   = "AKS"
  }
}
```

## Examples

### Basic User-Assigned Identity

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  resource_group_name = "rg-aks-dev-eastus"
  location            = "eastus"
  identity_type       = "UserAssigned"
  user_assigned_identity_name = "id-aks-dev-eastus"
}
```

### Using Existing Identity

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  resource_group_name = "rg-aks-dev-eastus"
  location            = "eastus"
  identity_type       = "UserAssigned"
  create_user_assigned_identity = false
  existing_user_assigned_identity_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-identities/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-aks-dev-eastus"
}
```

### Workload Identity Federation

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  resource_group_name = "rg-aks-prod-eastus"
  location            = "eastus"
  identity_type       = "UserAssigned"
  user_assigned_identity_name = "id-aks-prod-eastus"
  
  # Workload Identity settings
  enable_workload_identity = true
  oidc_issuer_enabled = true
  workload_identity_enabled = true
  
  # Optional: Customize federation settings
  federated_identity_credential_audiences = ["api://AzureADTokenExchange"]
  federated_identity_credential_subject = "system:serviceaccount:default:workload-identity-sa"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "AKS"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |
| azuread | >= 2.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |
| azuread | >= 2.0.0 |

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| resource_group_name | Name of the resource group where the identity will be created | `string` |
| location | Azure region where resources will be created | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| identity_type | Type of identity to use (SystemAssigned, UserAssigned, or Both) | `string` | `"UserAssigned"` | no |
| user_assigned_identity_name | Name of the user assigned identity (required when identity_type contains UserAssigned) | `string` | `null` | no |
| create_user_assigned_identity | Whether to create a new user assigned identity | `bool` | `true` | no |
| existing_user_assigned_identity_id | ID of an existing user assigned identity (when create_user_assigned_identity is false) | `string` | `null` | no |
| enable_workload_identity | Whether to enable workload identity federation | `bool` | `false` | no |
| oidc_issuer_enabled | Whether the OIDC issuer is enabled for workload identity | `bool` | `true` | no |
| workload_identity_enabled | Whether the workload identity feature is enabled | `bool` | `true` | no |
| federated_identity_credential_audiences | Audiences for federated identity credentials | `list(string)` | `["api://AzureADTokenExchange"]` | no |
| federated_identity_credential_issuer | Issuer for federated identity credentials | `string` | `null` | no |
| federated_identity_credential_subject | Subject for federated identity credentials | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| principal_id | The principal ID of the AKS identity |
| client_id | The client ID of the AKS identity |
| identity_ids | List of user assigned identity IDs |
| identity_id | The ID of the user assigned identity |
| kubelet_identity | The kubelet identity properties |
| oidc_issuer_url | The OIDC issuer URL for workload identity |

## Module Resources

This module creates the following resources:
- User-assigned managed identity (when create_user_assigned_identity is true)
- Azure Federated Identity Credential (when enable_workload_identity is true)

## Identity Types Explained

This module supports different identity configurations for AKS clusters:

1. **System-assigned managed identity**: Azure automatically creates an identity for the AKS cluster in Azure AD. This is simpler to manage but has fewer customization options.

2. **User-assigned managed identity**: You provide a pre-created identity or have the module create one. This provides more flexibility and allows for identity reuse across multiple resources.

3. **Both system and user-assigned**: Combines both approaches, using system-assigned for core functionality and user-assigned for specific permissions or workloads.

## Workload Identity Federation

When `enable_workload_identity` is set to `true`, the module configures workload identity federation, allowing:

- Kubernetes service accounts to authenticate directly with Azure AD
- Pods to access Azure resources securely without storing credentials
- Fine-grained access control through Azure RBAC

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation
- [naming](../naming) - For standardized resource naming

This module is designed to work with:
- [aks_core](../aks_core) - For the main AKS cluster configuration

## Notes

- When using an existing identity, ensure it has all necessary permissions for AKS operation
- For production workloads, using user-assigned identities is recommended for better security and management
- Workload identity is the modern recommended approach for pod authentication with Azure resources
- The `federated_identity_credential_issuer` requires the OIDC issuer URL from an existing AKS cluster

## License

This module is licensed under the MIT License. 