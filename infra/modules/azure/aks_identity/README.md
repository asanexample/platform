# Azure AKS Identity Module

This module creates and configures identities for Azure Kubernetes Service (AKS) clusters, implementing secure identity management and workload identity federation.

## Features

- Configures managed identities or service principals for AKS clusters
- Implements workload identity federation for secure pod authentication
- Sets up appropriate RBAC permissions for cluster identities
- Supports Azure AD integration for identity management
- Compatible with both system-assigned and user-assigned identities

## Usage

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  # Basic settings
  resource_group_name = "vip-rg-dev-eus-aks"
  location            = "eastus"
  
  # Identity settings
  identity_type       = "UserAssigned"
  user_assigned_identity_name = "vip-uami-dev-eus-aks"
  
  # Optional: Workload Identity Federation settings
  enable_workload_identity = true
  
  # Tags
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Component   = "AKS"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | >= 3.0.0 |
| azuread | >= 2.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | Name of the resource group | `string` | n/a | yes |
| location | Azure region where resources will be created | `string` | n/a | yes |
| identity_type | Type of identity to use for the AKS cluster (SystemAssigned, UserAssigned, SystemAssigned, UserAssigned) | `string` | `"UserAssigned"` | no |
| user_assigned_identity_name | Name of the user assigned identity for AKS (required when identity_type contains UserAssigned) | `string` | `null` | no |
| create_user_assigned_identity | Whether to create a new user assigned identity | `bool` | `true` | no |
| existing_user_assigned_identity_id | ID of an existing user assigned identity (if create_user_assigned_identity is false) | `string` | `null` | no |
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

## Identity Types

This module supports different identity configurations for AKS clusters:

1. **System-assigned managed identity**: Azure automatically creates an identity for the AKS cluster in Azure AD
2. **User-assigned managed identity**: You provide a pre-created identity or have the module create one
3. **Both system and user-assigned**: Combines both approaches for different purposes

## Workload Identity Federation

When `enable_workload_identity` is set to `true`, the module configures workload identity federation, which allows:

- Kubernetes service accounts to authenticate directly with Azure AD
- Pods to access Azure resources securely without storing credentials
- Fine-grained access control through Azure RBAC

### Configuring Workload Identity

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  resource_group_name = "vip-rg-dev-eus-aks"
  location            = "eastus"
  
  # Identity settings
  identity_type       = "UserAssigned"
  user_assigned_identity_name = "vip-uami-dev-eus-aks"
  
  # Workload Identity settings
  enable_workload_identity = true
  oidc_issuer_enabled = true
  workload_identity_enabled = true
  
  # The federated identity credential settings will be used
  # after the cluster is created with the OIDC issuer URL
}
```

## Integration with Other Modules

This module is designed to work with:

- [AKS Core Module](../aks_core/README.md): Provides the main AKS cluster configuration
- [AKS Cluster Module](../aks_cluster/README.md): Combines multiple AKS modules
- [AKS Cluster Composite Module](../aks_cluster_composite/README.md): Higher-level abstraction for AKS deployment

## License

This module is proprietary and confidential.

## Authors

VIP Platform Team 