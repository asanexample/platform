# Container Registry

Creates an Azure Container Registry (ACR) with configurable SKU, networking, encryption, geo-replication, and AKS integration. The module provisions the registry with a system-assigned identity, optional network rules and IP restrictions (Premium SKU), optional customer-managed key encryption, and AcrPull/AcrPush role assignments for AKS service principals. Registry names are auto-generated from workload, environment, and region if not explicitly provided.

## Usage

```hcl
module "acr" {
  source = "../../modules/azure/container_registry"

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"
  sku                 = "Standard"

  aks_integration_enabled = true
  aks_principal_id        = "00000000-0000-0000-0000-000000000000"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "acr" {
  source = "../../modules/azure/container_registry"
  create = false
}
```

### Premium with Geo-Replication and Network Rules

```hcl
module "acr" {
  source = "../../modules/azure/container_registry"

  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"
  workload            = "platform"
  environment         = "prod"
  region_abbv         = "eus"
  sku                 = "Premium"

  zone_redundancy_enabled       = true
  public_network_access_enabled = false
  geo_replication_locations     = ["westus2"]

  network_rule_set = {
    default_action = "Deny"
    ip_rules = [
      { action = "Allow", ip_range = "203.0.113.0/24" }
    ]
  }

  aks_integration_enabled = true
  aks_principal_id        = "00000000-0000-0000-0000-000000000000"
  enable_aks_acr_push     = true
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_container_registry.acr](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/container_registry) | resource |
| [azurerm_role_assignment.acr_pull](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.acr_push](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment for the resources | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The location for the ACR | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | The abbreviation for the Azure region | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The resource group name for the ACR | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | The workload identifier to use for resource names | `string` | n/a | yes |
| <a name="input_admin_enabled"></a> [admin\_enabled](#input\_admin\_enabled) | Whether to enable the admin user for the ACR | `bool` | `false` | no |
| <a name="input_aks_integration_enabled"></a> [aks\_integration\_enabled](#input\_aks\_integration\_enabled) | Whether to enable AKS integration for the ACR | `bool` | `false` | no |
| <a name="input_aks_principal_id"></a> [aks\_principal\_id](#input\_aks\_principal\_id) | The principal ID of the AKS cluster to integrate with the ACR (required if aks\_integration\_enabled is true) | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_create_registry"></a> [create\_registry](#input\_create\_registry) | Whether to create the Azure Container Registry | `bool` | `true` | no |
| <a name="input_data_endpoint_enabled"></a> [data\_endpoint\_enabled](#input\_data\_endpoint\_enabled) | Whether to enable the data endpoint for the ACR (Premium SKU only) | `bool` | `false` | no |
| <a name="input_enable_aks_acr_push"></a> [enable\_aks\_acr\_push](#input\_enable\_aks\_acr\_push) | Whether to enable AKS to push images to the ACR (if aks\_integration\_enabled is true) | `bool` | `false` | no |
| <a name="input_encryption_enabled"></a> [encryption\_enabled](#input\_encryption\_enabled) | Whether to enable encryption for the ACR (Premium SKU only) | `bool` | `false` | no |
| <a name="input_encryption_identity_id"></a> [encryption\_identity\_id](#input\_encryption\_identity\_id) | The ID of the user-assigned identity to use for encryption (Premium SKU only, required if encryption\_enabled is true) | `string` | `null` | no |
| <a name="input_geo_replication_locations"></a> [geo\_replication\_locations](#input\_geo\_replication\_locations) | The list of locations for geo-replication of the ACR (Premium SKU only) | `list(string)` | `[]` | no |
| <a name="input_key_vault_key_id"></a> [key\_vault\_key\_id](#input\_key\_vault\_key\_id) | The ID of the Key Vault key to use for encryption (Premium SKU only, required if encryption\_enabled is true) | `string` | `null` | no |
| <a name="input_lock_resource"></a> [lock\_resource](#input\_lock\_resource) | Whether to lock the resource to prevent accidental deletion | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the Azure Container Registry. If null, will use prefix, environment, and region\_abbv to create a name | `string` | `null` | no |
| <a name="input_network_rule_set"></a> [network\_rule\_set](#input\_network\_rule\_set) | The network rule set for the ACR (Premium SKU only). Only specify this when using Premium SKU. For Basic or Standard SKU, leave at the default value. | <pre>object({<br/>    default_action = string<br/>    ip_rules = list(object({<br/>      action   = string<br/>      ip_range = string<br/>    }))<br/>  })</pre> | <pre>{<br/>  "default_action": "Allow",<br/>  "ip_rules": []<br/>}</pre> | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether to enable public network access for the ACR | `bool` | `true` | no |
| <a name="input_retention_policy_days"></a> [retention\_policy\_days](#input\_retention\_policy\_days) | The number of days to retain images for in the ACR (Premium SKU only, 0 to disable) | `number` | `0` | no |
| <a name="input_sku"></a> [sku](#input\_sku) | The SKU of the ACR (Basic, Standard, Premium) | `string` | `"Standard"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | The tags to assign to the resources | `map(string)` | `{}` | no |
| <a name="input_zone_redundancy_enabled"></a> [zone\_redundancy\_enabled](#input\_zone\_redundancy\_enabled) | Whether to enable zone redundancy for the ACR (Premium SKU only) | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_acr_pull_role_assignment_id"></a> [acr\_pull\_role\_assignment\_id](#output\_acr\_pull\_role\_assignment\_id) | The ID of the AcrPull role assignment (if AKS integration is enabled). |
| <a name="output_acr_push_role_assignment_id"></a> [acr\_push\_role\_assignment\_id](#output\_acr\_push\_role\_assignment\_id) | The ID of the AcrPush role assignment (if AKS integration and push are enabled). |
| <a name="output_admin_enabled"></a> [admin\_enabled](#output\_admin\_enabled) | Whether admin access is enabled. |
| <a name="output_admin_password"></a> [admin\_password](#output\_admin\_password) | The Admin Password for the Container Registry. |
| <a name="output_admin_username"></a> [admin\_username](#output\_admin\_username) | The Admin Username for the Container Registry. |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_created"></a> [created](#output\_created) | Indicates whether the ACR was created by this module. |
| <a name="output_encryption_enabled"></a> [encryption\_enabled](#output\_encryption\_enabled) | Whether encryption is enabled. |
| <a name="output_geo_replications"></a> [geo\_replications](#output\_geo\_replications) | The geo-replications of the ACR. |
| <a name="output_id"></a> [id](#output\_id) | The ID of the Azure Container Registry. |
| <a name="output_identity"></a> [identity](#output\_identity) | The managed identity assigned to the Container Registry. |
| <a name="output_location"></a> [location](#output\_location) | The Azure region where the ACR exists. |
| <a name="output_login_server"></a> [login\_server](#output\_login\_server) | The URL that can be used to log into the container registry. |
| <a name="output_name"></a> [name](#output\_name) | The name of the Azure Container Registry. |
| <a name="output_network_rule_set"></a> [network\_rule\_set](#output\_network\_rule\_set) | The network rule set for the ACR. |
| <a name="output_public_network_access_enabled"></a> [public\_network\_access\_enabled](#output\_public\_network\_access\_enabled) | Whether public network access is enabled. |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group in which the ACR exists. |
| <a name="output_sku"></a> [sku](#output\_sku) | The SKU of the Azure Container Registry. |
| <a name="output_zone_redundancy_enabled"></a> [zone\_redundancy\_enabled](#output\_zone\_redundancy\_enabled) | Whether zone redundancy is enabled. |
<!-- END_TF_DOCS -->

## Notes

- ACR names must be globally unique, 5-50 characters, and alphanumeric only. The auto-generated name follows the pattern `{workload}{environment}acr{region_abbv}`.
- Geo-replication, network rules, zone redundancy, data endpoints, and encryption are only available with the Premium SKU.
- AKS integration creates an AcrPull role assignment. Set `enable_aks_acr_push = true` to also grant AcrPush.
- The `admin_enabled` flag defaults to false. Use Entra ID (Azure AD) authentication instead of admin credentials for production workloads.
