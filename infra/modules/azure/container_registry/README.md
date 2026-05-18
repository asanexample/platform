# Azure Container Registry Module

Creates an Azure Container Registry with optional AKS pull/push integration.

## Usage

```hcl
module "container_registry" {
  source = "../container_registry"

  create              = true
  create_registry     = true
  resource_group_name = module.resource_group.name
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"
  sku                 = "Standard"

  aks_integration_enabled = true
  aks_principal_id        = module.aks_core.kubelet_identity.object_id

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "container_registry" {
  source = "../container_registry"

  create              = false
  resource_group_name = "placeholder"
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"
}
```

### Registry disabled but module still called

```hcl
module "container_registry" {
  source = "../container_registry"

  create              = true
  create_registry     = false
  resource_group_name = module.resource_group.name
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_container_registry.acr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.acr_push](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | The environment for the resources | `string` | n/a | yes |
| location | The location for the ACR | `string` | n/a | yes |
| workload | The workload name to use for resource names | `string` | n/a | yes |
| region_abbv | The abbreviation for the Azure region | `string` | n/a | yes |
| resource_group_name | The resource group name for the ACR | `string` | n/a | yes |
| admin_enabled | Whether to enable the admin user for the ACR | `bool` | `false` | no |
| aks_integration_enabled | Whether to enable AKS integration for the ACR | `bool` | `false` | no |
| aks_principal_id | The principal ID of the AKS cluster to integrate with the ACR (required if aks_integration_enabled is true) | `string` | `null` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| create_registry | Whether to create the Azure Container Registry | `bool` | `true` | no |
| data_endpoint_enabled | Whether to enable the data endpoint for the ACR (Premium SKU only) | `bool` | `false` | no |
| enable_aks_acr_push | Whether to enable AKS to push images to the ACR (if aks_integration_enabled is true) | `bool` | `false` | no |
| encryption_enabled | Whether to enable encryption for the ACR (Premium SKU only) | `bool` | `false` | no |
| encryption_identity_id | The ID of the user-assigned identity to use for encryption (Premium SKU only, required if encryption_enabled is true) | `string` | `null` | no |
| geo_replication_locations | The list of locations for geo-replication of the ACR (Premium SKU only) | `list(string)` | `[]` | no |
| key_vault_key_id | The ID of the Key Vault key to use for encryption (Premium SKU only, required if encryption_enabled is true) | `string` | `null` | no |
| lock_resource | Whether to lock the resource to prevent accidental deletion | `bool` | `false` | no |
| name | The name of the Azure Container Registry. If null, will use prefix, environment, and region_abbv to create a name | `string` | `null` | no |
| network_rule_set | The network rule set for the ACR (Premium SKU only). Only specify this when using Premium SKU. For Basic or Standard SKU, leave at the default value. | <pre>object({<br/>    default_action = string<br/>    ip_rules = list(object({<br/>      action   = string<br/>      ip_range = string<br/>    }))<br/>  })</pre> | <pre>{<br/>  "default_action": "Allow",<br/>  "ip_rules": []<br/>}</pre> | no |
| public_network_access_enabled | Whether to enable public network access for the ACR | `bool` | `true` | no |
| retention_policy_days | The number of days to retain images for in the ACR (Premium SKU only, 0 to disable) | `number` | `0` | no |
| sku | The SKU of the ACR (Basic, Standard, Premium) | `string` | `"Standard"` | no |
| tags | The tags to assign to the resources | `map(string)` | `{}` | no |
| zone_redundancy_enabled | Whether to enable zone redundancy for the ACR (Premium SKU only) | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| acr_pull_role_assignment_id | The ID of the AcrPull role assignment (if AKS integration is enabled). |
| acr_push_role_assignment_id | The ID of the AcrPush role assignment (if AKS integration and push are enabled). |
| admin_enabled | Whether admin access is enabled. |
| admin_password | The Admin Password for the Container Registry. |
| admin_username | The Admin Username for the Container Registry. |
| create | Whether resources were created |
| created | Indicates whether the ACR was created by this module. |
| encryption_enabled | Whether encryption is enabled. |
| geo_replications | The geo-replications of the ACR. |
| id | The ID of the Azure Container Registry. |
| identity | The managed identity assigned to the Container Registry. |
| location | The Azure region where the ACR exists. |
| login_server | The URL that can be used to log into the container registry. |
| name | The name of the Azure Container Registry. |
| network_rule_set | The network rule set for the ACR. |
| public_network_access_enabled | Whether public network access is enabled. |
| resource_group_name | The name of the resource group in which the ACR exists. |
| sku | The SKU of the Azure Container Registry. |
| zone_redundancy_enabled | Whether zone redundancy is enabled. |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) -- standardized resource names
- [resource_group](../resource_group) -- resource group for the registry

## Notes

- Has a separate `create_registry` variable alongside `create`; `create` gates the entire module while `create_registry` gates only the ACR resource.
- Admin authentication is disabled by default; use AKS RBAC integration (`aks_integration_enabled`) instead.
- Premium SKU is required for geo-replication, zone redundancy, and customer-managed key encryption.
