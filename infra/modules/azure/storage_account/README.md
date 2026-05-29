# Storage Account

Creates an Azure Storage Account with configurable blob properties, network rules, lifecycle management, CORS, customer-managed key encryption, optional containers, and an optional private endpoint with DNS zone integration. The module supports all account kinds and replication types, and includes blob versioning, soft delete retention, change feed tracking, and tiering lifecycle policies. Default tags include `DataClassification = "Internal"` and `ManagedBy = "Terraform"`.

## Usage

```hcl
module "storage_account" {
  source = "../../modules/azure/storage_account"

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"

  name_components = {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }

  account_tier             = "Standard"
  account_replication_type = "ZRS"
  access_tier              = "Hot"

  containers = {
    "tfstate" = {
      name                  = "tfstate"
      container_access_type = "private"
    }
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
module "storage_account" {
  source = "../../modules/azure/storage_account"
  create = false
}
```

### Private Endpoint with Lifecycle Rules

```hcl
module "storage_account" {
  source = "../../modules/azure/storage_account"

  name                = "stplatprodeus001"
  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"

  account_replication_type      = "GRS"
  shared_access_key_enabled     = false
  public_network_access_enabled = false

  blob_versioning_enabled        = true
  blob_delete_retention_days     = 30
  container_delete_retention_days = 7

  lifecycle_rules = [
    {
      name         = "archive-old-logs"
      prefix_match = ["logs/"]
      tier_to_cool_action = {
        days_after_modification_greater_than = 30
      }
      tier_to_archive_action = {
        days_after_modification_greater_than = 90
      }
      delete_action = {
        days_after_modification_greater_than = 365
      }
    }
  ]

  private_endpoint = {
    create               = true
    subnet_id            = "/subscriptions/.../subnets/snet-endpoint"
    subresource_names    = ["blob"]
    private_dns_zone_ids = ["/subscriptions/.../privateDnsZones/privatelink.blob.core.windows.net"]
  }

  network_rules = {
    default_action = "Deny"
    bypass         = ["AzureServices"]
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
| [azurerm_private_endpoint.storage](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_endpoint) | resource |
| [azurerm_storage_account.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_account) | resource |
| [azurerm_storage_container.containers](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |
| [azurerm_storage_management_policy.lifecycle](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_management_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region where resources will be deployed | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to deploy the storage account in | `string` | n/a | yes |
| <a name="input_access_tier"></a> [access\_tier](#input\_access\_tier) | Access tier for the storage account | `string` | `"Hot"` | no |
| <a name="input_account_kind"></a> [account\_kind](#input\_account\_kind) | Kind of storage account to create | `string` | `"StorageV2"` | no |
| <a name="input_account_replication_type"></a> [account\_replication\_type](#input\_account\_replication\_type) | Replication type for the storage account | `string` | `"LRS"` | no |
| <a name="input_account_tier"></a> [account\_tier](#input\_account\_tier) | Tier of storage account to create | `string` | `"Standard"` | no |
| <a name="input_allow_nested_items_to_be_public"></a> [allow\_nested\_items\_to\_be\_public](#input\_allow\_nested\_items\_to\_be\_public) | Whether nested items (blobs, containers) can be set to public access | `bool` | `false` | no |
| <a name="input_blob_delete_retention_days"></a> [blob\_delete\_retention\_days](#input\_blob\_delete\_retention\_days) | Number of days to retain deleted blobs. If specified, must be between 1 and 365. | `number` | `null` | no |
| <a name="input_blob_public_access_enabled"></a> [blob\_public\_access\_enabled](#input\_blob\_public\_access\_enabled) | Whether public access is allowed to containers and blobs | `bool` | `false` | no |
| <a name="input_blob_versioning_enabled"></a> [blob\_versioning\_enabled](#input\_blob\_versioning\_enabled) | Whether blob versioning is enabled | `bool` | `false` | no |
| <a name="input_change_feed_enabled"></a> [change\_feed\_enabled](#input\_change\_feed\_enabled) | Whether the change feed is enabled | `bool` | `false` | no |
| <a name="input_container_delete_retention_days"></a> [container\_delete\_retention\_days](#input\_container\_delete\_retention\_days) | Number of days to retain deleted containers. If specified, must be between 1 and 365. | `number` | `null` | no |
| <a name="input_containers"></a> [containers](#input\_containers) | List of containers to create in the storage account | <pre>map(object({<br/>    name                  = string<br/>    container_access_type = optional(string, "private")<br/>  }))</pre> | `{}` | no |
| <a name="input_cors_rules"></a> [cors\_rules](#input\_cors\_rules) | CORS rules for the storage account blob service | <pre>list(object({<br/>    allowed_origins    = list(string) # List of origin domains that are permitted to make requests<br/>    allowed_methods    = list(string) # HTTP methods that are allowed (GET, PUT, POST, DELETE, HEAD, OPTIONS)<br/>    allowed_headers    = list(string) # HTTP request headers that are supported<br/>    exposed_headers    = list(string) # Response headers that browsers are allowed to access<br/>    max_age_in_seconds = number       # How long browsers should cache CORS preflight response<br/>  }))</pre> | `[]` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_create_containers"></a> [create\_containers](#input\_create\_containers) | Whether to create containers as part of this module. Set to false if you want to manage containers separately. | `bool` | `true` | no |
| <a name="input_customer_managed_key"></a> [customer\_managed\_key](#input\_customer\_managed\_key) | Customer-managed key configuration for storage account encryption | <pre>object({<br/>    key_vault_key_id             = string                 # ID of the key vault key used for encryption<br/>    user_assigned_identity_id    = optional(string, null) # ID of user-assigned managed identity with key access<br/>    use_system_assigned_identity = optional(bool, false)  # Whether to use system-assigned identity instead<br/><br/>    # Optional key auto-rotation settings<br/>    key_rotation = optional(object({<br/>      auto_rotation_enabled  = optional(bool, false) # Whether key auto-rotation is enabled<br/>      rotation_interval_days = optional(number, 90)  # Number of days before auto-rotating the key<br/>    }), {})<br/>  })</pre> | `null` | no |
| <a name="input_last_access_time_enabled"></a> [last\_access\_time\_enabled](#input\_last\_access\_time\_enabled) | Whether last access time tracking is enabled | `bool` | `false` | no |
| <a name="input_lifecycle_rules"></a> [lifecycle\_rules](#input\_lifecycle\_rules) | Lifecycle rules for blob storage | <pre>list(object({<br/>    name         = string<br/>    enabled      = optional(bool, true)<br/>    prefix_match = optional(list(string), [])<br/><br/>    delete_action = optional(object({<br/>      days_after_modification_greater_than = number<br/>    }), null)<br/><br/>    tier_to_cool_action = optional(object({<br/>      days_after_modification_greater_than = number<br/>    }), null)<br/><br/>    tier_to_archive_action = optional(object({<br/>      days_after_modification_greater_than = number<br/>    }), null)<br/>  }))</pre> | `[]` | no |
| <a name="input_min_tls_version"></a> [min\_tls\_version](#input\_min\_tls\_version) | Minimum TLS version required by the storage account | `string` | `"TLS1_2"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the storage account (if custom naming is required). If not provided, it will be auto-generated based on prefix, environment, region and instance components. | `string` | `null` | no |
| <a name="input_name_components"></a> [name\_components](#input\_name\_components) | Components to auto-generate the storage account name if 'name' is not provided | <pre>object({<br/>    workload    = optional(string, "platform")<br/>    environment = optional(string, "dev")<br/>    region_abbv = optional(string, "eus")<br/>    instance    = optional(string, "001")<br/>  })</pre> | `{}` | no |
| <a name="input_network_rules"></a> [network\_rules](#input\_network\_rules) | Network rules for the storage account | <pre>object({<br/>    default_action             = optional(string, "Allow")<br/>    bypass                     = optional(list(string), ["AzureServices"])<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| <a name="input_private_endpoint"></a> [private\_endpoint](#input\_private\_endpoint) | Configuration for private endpoint if required | <pre>object({<br/>    create               = optional(bool, false)<br/>    name                 = optional(string, "")<br/>    subnet_id            = optional(string, "")<br/>    private_dns_zone_ids = optional(list(string), [])<br/>    subresource_names    = optional(list(string), ["blob"])<br/>  })</pre> | `{}` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether public network access is enabled for the storage account (independent of private endpoint configuration) | `bool` | `true` | no |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | List of role assignments to create for Entra ID authentication. Should contain principal\_id, role\_definition\_name or role\_definition\_id, and scope (optional). | <pre>list(object({<br/>    principal_id         = string<br/>    role_definition_name = optional(string, null)<br/>    role_definition_id   = optional(string, null)<br/>    description          = optional(string, null)<br/>    scope                = optional(string, null) # Defaults to storage account resource ID<br/>  }))</pre> | `[]` | no |
| <a name="input_shared_access_key_enabled"></a> [shared\_access\_key\_enabled](#input\_shared\_access\_key\_enabled) | Whether shared access key authentication is enabled (not recommended, Entra ID authentication is preferred) | `bool` | `false` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_containers"></a> [containers](#output\_containers) | Map of created containers with their properties |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_id"></a> [id](#output\_id) | ID of the created storage account |
| <a name="output_name"></a> [name](#output\_name) | Name of the created storage account |
| <a name="output_primary_access_key"></a> [primary\_access\_key](#output\_primary\_access\_key) | Primary access key for the storage account. DEPRECATED: Use Entra ID authentication instead of access keys. |
| <a name="output_primary_blob_endpoint"></a> [primary\_blob\_endpoint](#output\_primary\_blob\_endpoint) | Primary blob endpoint for the storage account |
| <a name="output_primary_connection_string"></a> [primary\_connection\_string](#output\_primary\_connection\_string) | Primary connection string for the storage account. DEPRECATED: Use Entra ID authentication instead of connection strings. |
| <a name="output_private_endpoint_ids"></a> [private\_endpoint\_ids](#output\_private\_endpoint\_ids) | List of private endpoint IDs if created |
| <a name="output_secondary_access_key"></a> [secondary\_access\_key](#output\_secondary\_access\_key) | Secondary access key for the storage account. DEPRECATED: Use Entra ID authentication instead of access keys. |
| <a name="output_secondary_connection_string"></a> [secondary\_connection\_string](#output\_secondary\_connection\_string) | Secondary connection string for the storage account. DEPRECATED: Use Entra ID authentication instead of connection strings. |
<!-- END_TF_DOCS -->

## Notes

- Storage account names must be globally unique, 3-24 characters, lowercase alphanumeric only. Auto-generated names follow `{workload}{environment}{region_abbv}sa{instance}`.
- Shared access key authentication is disabled by default (`shared_access_key_enabled = false`). Use Entra ID (Azure AD) RBAC for authentication instead.
- When `private_endpoint.create = true`, network rules are automatically applied with the configured `default_action`. The private endpoint supports subresources: `blob`, `queue`, `table`, `file`, `web`, `dfs`.
- Customer-managed key encryption requires either a user-assigned identity or system-assigned identity with access to the specified Key Vault key.
- Container creation can be decoupled from the storage account by setting `create_containers = false` and using the `storage_container` module separately.
