# Azure Container Registry Module

This Terraform module deploys an Azure Container Registry (ACR) instance with various configuration options and supports integration with Azure Kubernetes Service (AKS).

## Features

- Optional provisioning - enabled by default, can be disabled via a single variable
- Supports all ACR SKUs (Basic, Standard, Premium)
- Configurable network access controls
- Integration with AKS through RBAC
- Support for geo-replication (Premium SKU)
- Encryption support (Premium SKU)
- Resource locking capabilities
- Image retention policies
- Consistent tagging and naming conventions

## Usage

### Basic Example

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  resource_group_name = "my-resource-group"
  location            = "eastus"
  environment         = "dev"
  region_abbv         = "eus"
  
  # Optional: Specify a custom name (otherwise generated from prefix/env/region)
  # name = "mydevregistry"
  
  # Default SKU is Standard
  sku = "Standard"
  
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

### Disabling ACR Creation

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  create_registry     = false
  resource_group_name = "my-resource-group"
  location            = "eastus"
  environment         = "dev"
  region_abbv         = "eus"
}
```

### Premium SKU with AKS Integration

```hcl
module "acr" {
  source              = "../../modules/azure/container_registry"
  resource_group_name = "my-resource-group"
  location            = "eastus"
  environment         = "prod"
  region_abbv         = "eus"
  
  sku                     = "Premium"
  zone_redundancy_enabled = true
  
  # AKS integration
  aks_integration_enabled = true
  aks_principal_id        = module.aks.kubelet_identity_id
  
  # Network rules (Premium/Standard only)
  network_rule_set = {
    default_action  = "Deny"
    ip_rules        = ["203.0.113.0/24"]
  }
  
  # Premium features
  geo_replication_locations = [
    {
      location                = "westus"
      zone_redundancy_enabled = true
    }
  ]
  
  # Retention policy for images (days)
  retention_policy_days = 90
  
  tags = {
    Environment = "Production"
    Project     = "MyProject"
    CostCenter  = "IT"
  }
}
```

## Security Best Practices

This module implements several security best practices:

1. **RBAC Integration**: Uses Azure RBAC instead of admin credentials for AKS integration
2. **Network Restrictions**: Supports network access control with IP and VNET rules
3. **Limited Admin Access**: Admin access is disabled by default
4. **Encryption**: Support for customer-managed keys (Premium SKU)
5. **Resource Locking**: Optional resource locks to prevent accidental deletion

## AKS Integration

The module supports integration with AKS in two ways:

1. **AcrPull Role**: Grants the AKS cluster identity pull access to the registry
2. **AcrPush Role** (Optional): Can grant the AKS cluster identity push access to the registry

These role assignments enable AKS to pull images without requiring registry admin credentials, which is more secure and follows Azure best practices.

### Example AKS Integration Workflow

1. Deploy the ACR module with AKS integration enabled
2. Deploy applications to AKS that reference images in the ACR using the registry's login server URL
3. AKS will automatically authenticate with ACR using managed identity

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| resource_group_name | The name of the resource group | string |
| location | Azure region | string | 
| environment | Environment name (dev, prod, etc.) | string |
| region_abbv | Abbreviated region name | string |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| create_registry | Whether to create the ACR | bool | true |
| name | Custom registry name | string | null (auto-generated) |
| sku | ACR SKU (Basic, Standard, Premium) | string | "Standard" |
| admin_enabled | Enable admin access | bool | false |
| public_network_access_enabled | Enable public network access | bool | true |
| zone_redundancy_enabled | Enable zone redundancy (Premium only) | bool | false |
| data_endpoint_enabled | Enable data endpoint (Premium only) | bool | false |
| geo_replication_locations | Locations for geo-replication (Premium only) | list(object) | [] |
| network_rule_set | Network access rules | object | null |
| encryption_enabled | Enable encryption (Premium only) | bool | false |
| key_vault_key_id | Key Vault key ID for encryption | string | null |
| encryption_identity_id | User identity for encryption | string | null |
| lock_resource | Apply deletion lock | bool | false |
| retention_policy_days | Image retention days | number | 0 |
| aks_integration_enabled | Enable AKS integration | bool | false |
| aks_principal_id | AKS identity principal ID | string | null |
| enable_aks_acr_push | Enable AKS push access | bool | false |
| tags | Resource tags | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| id | ACR resource ID |
| name | ACR name |
| login_server | ACR login server URL |
| admin_username | Admin username (if enabled) |
| admin_password | Admin password (if enabled) |
| identity | Managed identity details |
| resource_group_name | Resource group name |
| location | Azure region |
| sku | ACR SKU |
| admin_enabled | Whether admin access is enabled |
| public_network_access_enabled | Whether public access is enabled |
| zone_redundancy_enabled | Whether zone redundancy is enabled |
| network_rule_set | Network rule set configuration |
| geo_replications | Geo-replication configuration |
| encryption_enabled | Whether encryption is enabled |
| acr_pull_role_assignment_id | AcrPull role assignment ID |
| acr_push_role_assignment_id | AcrPush role assignment ID |
| lock_id | Resource lock ID |

## Notes

- The Basic SKU does not support network rules, geo-replication, or encryption
- Premium SKU is required for geo-replication, zone redundancy, and customer-managed keys
- The module requires the AzureRM provider version 4.0.0 or higher
- Image retention policy must be managed through Azure Portal or CLI as Terraform does not currently support it
- Virtual Network rules are not supported in this module version; use IP rules instead

## License

This module is licensed under the MIT License - see the [LICENSE](LICENSE) file for details. 