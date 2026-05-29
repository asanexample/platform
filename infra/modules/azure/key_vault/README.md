# Key Vault

Creates an Azure Key Vault with configurable access control (RBAC or access policies), network ACLs, and an optional private endpoint with private DNS zone integration. The module supports both standard and premium SKUs, purge protection, soft delete retention, and disk encryption enablement. When a private endpoint is created, public network access is automatically disabled.

## Usage

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  resource_group_name       = "rg-platform-dev-eus"
  location                  = "eastus"
  enable_rbac_authorization = true
  sku_name                  = "standard"

  name_components = {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"
  create = false
}
```

### Private Endpoint with Access Policies

```hcl
module "key_vault" {
  source = "../../modules/azure/key_vault"

  name                      = "kv-plat-prod-eus"
  resource_group_name       = "rg-platform-prod-eus"
  location                  = "eastus"
  enable_rbac_authorization = false

  access_policies = {
    "deployer" = {
      object_id          = "00000000-0000-0000-0000-000000000000"
      secret_permissions = ["Get", "List", "Set"]
      key_permissions    = ["Get", "List"]
    }
  }

  private_endpoint = {
    create               = true
    subnet_id            = "/subscriptions/.../subnets/snet-endpoint"
    private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.vaultcore.azure.net"]
  }

  network_acls = {
    bypass         = "AzureServices"
    default_action = "Deny"
  }
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
| [azurerm_key_vault.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault) | resource |
| [azurerm_key_vault_access_policy.policies](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/key_vault_access_policy) | resource |
| [azurerm_private_endpoint.key_vault](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the key vault will be deployed | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to deploy the key vault in | `string` | n/a | yes |
| <a name="input_access_policies"></a> [access\_policies](#input\_access\_policies) | Map of access policies for the key vault (used only when RBAC authorization is disabled) | <pre>map(object({<br/>    tenant_id               = optional(string)<br/>    object_id               = string<br/>    key_permissions         = optional(list(string), [])<br/>    secret_permissions      = optional(list(string), [])<br/>    certificate_permissions = optional(list(string), [])<br/>    storage_permissions     = optional(list(string), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_enable_rbac_authorization"></a> [enable\_rbac\_authorization](#input\_enable\_rbac\_authorization) | Whether to enable RBAC authorization for the key vault | `bool` | `true` | no |
| <a name="input_enabled_for_disk_encryption"></a> [enabled\_for\_disk\_encryption](#input\_enabled\_for\_disk\_encryption) | Whether the key vault is enabled for disk encryption | `bool` | `false` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the key vault (if custom naming is required). If not provided, it will be auto-generated based on naming components. | `string` | `null` | no |
| <a name="input_name_components"></a> [name\_components](#input\_name\_components) | Components to auto-generate the key vault name if 'name' is not provided | <pre>object({<br/>    workload    = optional(string, "platform")<br/>    environment = optional(string, "dev")<br/>    region_abbv = optional(string, "eus")<br/>    instance    = optional(string, "001")<br/>  })</pre> | `{}` | no |
| <a name="input_network_acls"></a> [network\_acls](#input\_network\_acls) | Network ACLs for the key vault | <pre>object({<br/>    bypass                     = optional(string, "AzureServices")<br/>    default_action             = optional(string, "Deny")<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `null` | no |
| <a name="input_private_endpoint"></a> [private\_endpoint](#input\_private\_endpoint) | Configuration for private endpoint if required | <pre>object({<br/>    create               = optional(bool, false)<br/>    name                 = optional(string, "")<br/>    subnet_id            = optional(string, "")<br/>    private_dns_zone_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether public network access is enabled for the key vault | `bool` | `false` | no |
| <a name="input_purge_protection_enabled"></a> [purge\_protection\_enabled](#input\_purge\_protection\_enabled) | Whether purge protection is enabled for the key vault | `bool` | `true` | no |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | SKU name for the key vault (standard or premium) | `string` | `"standard"` | no |
| <a name="input_soft_delete_retention_days"></a> [soft\_delete\_retention\_days](#input\_soft\_delete\_retention\_days) | Number of days for soft delete retention (7-90 days) | `number` | `90` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_access_policy_ids"></a> [access\_policy\_ids](#output\_access\_policy\_ids) | IDs of the created access policies |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_id"></a> [id](#output\_id) | ID of the created Key Vault |
| <a name="output_name"></a> [name](#output\_name) | Name of the created Key Vault |
| <a name="output_private_endpoint_ids"></a> [private\_endpoint\_ids](#output\_private\_endpoint\_ids) | IDs of the created private endpoints |
| <a name="output_public_network_access_enabled"></a> [public\_network\_access\_enabled](#output\_public\_network\_access\_enabled) | Whether public network access is enabled for the Key Vault |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | Tenant ID of the Key Vault |
| <a name="output_uri"></a> [uri](#output\_uri) | URI of the created Key Vault |
<!-- END_TF_DOCS -->

## Notes

- RBAC authorization (`enable_rbac_authorization = true`) is the default and recommended approach. Access policies are only used when RBAC is disabled.
- When `private_endpoint.create = true`, `public_network_access_enabled` is automatically set to false regardless of its input value.
- Key Vault names must be globally unique, 3-24 characters, alphanumeric and hyphens only. The auto-generated name uses the `name_components` object.
- Purge protection is enabled by default with a 90-day soft delete retention. These settings cannot be reduced once set on an existing vault.
- Default tags include `DataClassification = "Confidential"` and `ManagedBy = "Terraform"`.
