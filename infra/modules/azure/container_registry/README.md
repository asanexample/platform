# Azure Container Registry Module

## Overview

This module creates and configures an Azure Container Registry (ACR) instance with comprehensive configuration options for security, networking, and integration with Azure Kubernetes Service (AKS). The module supports all ACR SKUs and their respective features.

## Features

- Flexible deployment with optional provisioning toggle
- Support for all ACR SKUs (Basic, Standard, Premium)
- Network access controls and security configurations
- AKS integration through Azure RBAC
- Premium features including geo-replication and zone redundancy
- Encryption configuration with customer-managed keys
- Resource locking to prevent accidental deletion
- Image retention policy management
- Standardized naming and tagging conventions

## Usage

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  resource_group_name = "rg-platform-dev-eastus"
  location            = "eastus"
  environment         = "dev"
  region_abbv         = "eus"
  
  # Optional: Specify a custom name (otherwise auto-generated)
  # name = "acrdeveus001"
  
  # Default SKU is Standard
  sku = "Standard"
  
  # Basic network security
  public_network_access_enabled = true
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
    Component   = "ContainerRegistry"
  }
}
```

## Examples

### Basic Registry (Development Environment)

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  resource_group_name = "rg-platform-dev-eastus"
  location            = "eastus"
  environment         = "dev"
  region_abbv         = "eus"
  
  sku = "Standard"
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Production Registry with Premium Features

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  resource_group_name = "rg-platform-prod-eastus"
  location            = "eastus"
  environment         = "prod"
  region_abbv         = "eus"
  
  sku                     = "Premium"
  zone_redundancy_enabled = true
  
  # Network security configuration
  public_network_access_enabled = false
  network_rule_set = {
    default_action = "Deny"
    ip_rules       = ["203.0.113.0/24", "198.51.100.0/24"]
  }
  
  # Geo-replication for disaster recovery
  geo_replication_locations = [
    {
      location                = "westus"
      zone_redundancy_enabled = true
    }
  ]
  
  # Retention policy for images (90 days)
  retention_policy_days = 90
  
  # Prevent accidental deletion
  lock_resource = true
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "ContainerRegistry"
    CostCenter  = "Platform"
  }
}
```

### AKS Integration with Secure Network Configuration

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  resource_group_name = "rg-platform-prod-eastus"
  location            = "eastus"
  environment         = "prod"
  region_abbv         = "eus"
  
  sku = "Premium"
  
  # AKS integration
  aks_integration_enabled = true
  aks_principal_id        = module.aks.kubelet_identity.object_id
  enable_aks_acr_push     = false  # Only allow pull operations
  
  # Network security
  public_network_access_enabled = false
  network_rule_set = {
    default_action = "Deny"
    ip_rules       = ["203.0.113.0/24"]
  }
  
  # Enhanced security
  admin_enabled = false
  encryption_enabled = true
  key_vault_key_id = module.key_vault.keys["acr-encryption"].id
  encryption_identity_id = module.identity.id
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "ContainerRegistry"
    Security    = "High"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| resource_group_name | The name of the resource group where the registry will be created | `string` |
| location | Azure region where the registry will be deployed | `string` |
| environment | Environment name for resource tagging and naming (dev, test, staging, prod) | `string` |
| region_abbv | Abbreviation for region (used in resource naming) | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| create_registry | Whether to create the Azure Container Registry | `bool` | `true` | no |
| name | Custom name for the registry (auto-generated if not provided) | `string` | `null` | no |
| sku | The SKU of the container registry (Basic, Standard, Premium) | `string` | `"Standard"` | no |
| admin_enabled | Whether admin authentication is enabled | `bool` | `false` | no |
| public_network_access_enabled | Whether public network access is enabled | `bool` | `true` | no |
| zone_redundancy_enabled | Whether zone redundancy is enabled (Premium SKU only) | `bool` | `false` | no |
| data_endpoint_enabled | Whether to enable dedicated data endpoints (Premium SKU only) | `bool` | `false` | no |
| geo_replication_locations | Locations for geo-replication (Premium SKU only) | `list(object)` | `[]` | no |
| network_rule_set | Network rules for controlling access (Standard/Premium SKU only) | `object` | `null` | no |
| encryption_enabled | Whether to enable encryption with customer-managed keys (Premium SKU only) | `bool` | `false` | no |
| key_vault_key_id | The ID of the Key Vault key for encryption | `string` | `null` | no |
| encryption_identity_id | The ID of the user-assigned identity for encryption | `string` | `null` | no |
| lock_resource | Whether to apply a deletion lock to prevent accidental deletion | `bool` | `false` | no |
| retention_policy_days | Number of days to retain images (0 means disabled) | `number` | `0` | no |
| aks_integration_enabled | Whether to enable AKS integration | `bool` | `false` | no |
| aks_principal_id | The principal ID of the AKS identity for RBAC | `string` | `null` | no |
| enable_aks_acr_push | Whether to grant AKS push access (in addition to pull) | `bool` | `false` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Container Registry |
| name | The name of the Azure Container Registry |
| login_server | The login server URL (e.g., myregistry.azurecr.io) |
| admin_username | The admin username (if admin authentication is enabled) |
| admin_password | The admin password (if admin authentication is enabled) |
| identity | The managed identity details |
| resource_group_name | The name of the resource group containing the registry |
| location | The location of the registry |
| sku | The SKU of the registry |
| admin_enabled | Whether admin authentication is enabled |
| public_network_access_enabled | Whether public network access is enabled |
| zone_redundancy_enabled | Whether zone redundancy is enabled |
| network_rule_set | The network rule set configuration |
| geo_replications | The geo-replication configuration |
| encryption_enabled | Whether encryption is enabled |
| acr_pull_role_assignment_id | The ID of the AcrPull role assignment |
| acr_push_role_assignment_id | The ID of the AcrPush role assignment |
| lock_id | The ID of the resource lock (if enabled) |

## Module Resources

This module creates the following resources:
- Azure Container Registry
- Role assignments for AKS integration (when enabled)
- Resource lock (when enabled)

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation
- [aks_core](../aks_core) - For AKS integration
- [key_vault](../key_vault) - For encryption with customer-managed keys
- [identities](../identities) - For user-assigned identity for encryption

## Security Best Practices

This module implements several security best practices:

1. **RBAC Integration**: Uses Azure RBAC instead of admin credentials for AKS integration
2. **Network Restrictions**: Supports network access control with IP rules
3. **Limited Admin Access**: Admin access is disabled by default
4. **Encryption**: Support for customer-managed keys (Premium SKU)
5. **Resource Locking**: Optional resource locks to prevent accidental deletion

## AKS Integration

The module supports integration with AKS in two ways:

1. **AcrPull Role**: Grants the AKS cluster identity pull access to the registry
2. **AcrPush Role** (Optional): Can grant the AKS cluster identity push access to the registry

These role assignments enable AKS to pull images without requiring registry admin credentials, which is more secure and follows Azure best practices.

## Notes

- The Basic SKU does not support network rules, geo-replication, or encryption
- Premium SKU is required for geo-replication, zone redundancy, and customer-managed keys
- Network rules require Standard or Premium SKU
- Virtual Network rules are not supported in this module version; use IP rules instead
- Image retention policy only applies to untagged manifests
- When using geo-replication, consider using Premium SKU with zone redundancy for production workloads

## License

This module is licensed under the MIT License. 