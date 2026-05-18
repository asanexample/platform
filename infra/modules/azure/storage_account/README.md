# Azure Storage Account Module

Creates a storage account with lifecycle rules, optional containers, and optional private endpoint.

## Usage

```hcl
module "storage_account" {
  source = "../storage_account"

  create = true

  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"
  name                = "platformprodeus001"

  account_tier             = "Standard"
  account_replication_type = "ZRS"
  shared_access_key_enabled = false

  lifecycle_rules = [
    {
      name    = "archive-old-blobs"
      enabled = true
      tier_to_cool_action = {
        days_after_modification_greater_than = 30
      }
      delete_action = {
        days_after_modification_greater_than = 365
      }
    }
  ]

  private_endpoint = {
    create               = true
    subnet_id            = module.networking.subnet_ids["endpoints"]
    private_dns_zone_ids = [module.private_dns.private_dns_zone_ids["blob"]]
  }

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "storage_account" {
  source = "../storage_account"
  create = false
}
```

### Auto-generated name

```hcl
module "storage_account" {
  source = "../storage_account"

  create = true

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"

  name_components = {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

<!-- BEGIN_TF_DOCS -->
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
| location | Azure region where resources will be deployed | `string` | n/a | yes |
| resource_group_name | Name of the resource group to deploy the storage account in | `string` | n/a | yes |
| access_tier | Access tier for the storage account | `string` | `"Hot"` | no |
| account_kind | Kind of storage account to create | `string` | `"StorageV2"` | no |
| account_replication_type | Replication type for the storage account | `string` | `"LRS"` | no |
| account_tier | Tier of storage account to create | `string` | `"Standard"` | no |
| allow_nested_items_to_be_public | Whether nested items (blobs, containers) can be set to public access | `bool` | `false` | no |
| blob_delete_retention_days | Number of days to retain deleted blobs. If specified, must be between 1 and 365. | `number` | `null` | no |
| blob_public_access_enabled | Whether public access is allowed to containers and blobs | `bool` | `false` | no |
| blob_versioning_enabled | Whether blob versioning is enabled | `bool` | `false` | no |
| change_feed_enabled | Whether the change feed is enabled | `bool` | `false` | no |
| container_delete_retention_days | Number of days to retain deleted containers. If specified, must be between 1 and 365. | `number` | `null` | no |
| containers | List of containers to create in the storage account | <pre>map(object({<br/>    name                  = string<br/>    container_access_type = optional(string, "private")<br/>  }))</pre> | `{}` | no |
| cors_rules | CORS rules for the storage account blob service | <pre>list(object({<br/>    allowed_origins    = list(string) # List of origin domains that are permitted to make requests<br/>    allowed_methods    = list(string) # HTTP methods that are allowed (GET, PUT, POST, DELETE, HEAD, OPTIONS)<br/>    allowed_headers    = list(string) # HTTP request headers that are supported<br/>    exposed_headers    = list(string) # Response headers that browsers are allowed to access<br/>    max_age_in_seconds = number       # How long browsers should cache CORS preflight response<br/>  }))</pre> | `[]` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| create_containers | Whether to create containers as part of this module. Set to false if you want to manage containers separately. | `bool` | `true` | no |
| customer_managed_key | Customer-managed key configuration for storage account encryption | <pre>object({<br/>    key_vault_key_id             = string                 # ID of the key vault key used for encryption<br/>    user_assigned_identity_id    = optional(string, null) # ID of user-assigned managed identity with key access<br/>    use_system_assigned_identity = optional(bool, false)  # Whether to use system-assigned identity instead<br/><br/>    # Optional key auto-rotation settings<br/>    key_rotation = optional(object({<br/>      auto_rotation_enabled  = optional(bool, false) # Whether key auto-rotation is enabled<br/>      rotation_interval_days = optional(number, 90)  # Number of days before auto-rotating the key<br/>    }), {})<br/>  })</pre> | `null` | no |
| last_access_time_enabled | Whether last access time tracking is enabled | `bool` | `false` | no |
| lifecycle_rules | Lifecycle rules for blob storage | <pre>list(object({<br/>    name         = string<br/>    enabled      = optional(bool, true)<br/>    prefix_match = optional(list(string), [])<br/><br/>    delete_action = optional(object({<br/>      days_after_modification_greater_than = number<br/>    }), null)<br/><br/>    tier_to_cool_action = optional(object({<br/>      days_after_modification_greater_than = number<br/>    }), null)<br/><br/>    tier_to_archive_action = optional(object({<br/>      days_after_modification_greater_than = number<br/>    }), null)<br/>  }))</pre> | `[]` | no |
| min_tls_version | Minimum TLS version required by the storage account | `string` | `"TLS1_2"` | no |
| name | Name of the storage account (if custom naming is required). If not provided, it will be auto-generated based on prefix, environment, region and instance components. | `string` | `null` | no |
| name_components | Components to auto-generate the storage account name if 'name' is not provided | <pre>object({<br/>    workload    = optional(string, "platform")<br/>    environment = optional(string, "dev")<br/>    region_abbv = optional(string, "eus")<br/>    instance    = optional(string, "001")<br/>  })</pre> | `{}` | no |
| network_rules | Network rules for the storage account | <pre>object({<br/>    default_action             = optional(string, "Allow")<br/>    bypass                     = optional(list(string), ["AzureServices"])<br/>    ip_rules                   = optional(list(string), [])<br/>    virtual_network_subnet_ids = optional(list(string), [])<br/>  })</pre> | `{}` | no |
| private_endpoint | Configuration for private endpoint if required | <pre>object({<br/>    create               = optional(bool, false)<br/>    name                 = optional(string, "")<br/>    subnet_id            = optional(string, "")<br/>    private_dns_zone_ids = optional(list(string), [])<br/>    subresource_names    = optional(list(string), ["blob"])<br/>  })</pre> | `{}` | no |
| public_network_access_enabled | Whether public network access is enabled for the storage account (independent of private endpoint configuration) | `bool` | `true` | no |
| role_assignments | List of role assignments to create for Entra ID authentication. Should contain principal_id, role_definition_name or role_definition_id, and scope (optional). | <pre>list(object({<br/>    principal_id         = string<br/>    role_definition_name = optional(string, null)<br/>    role_definition_id   = optional(string, null)<br/>    description          = optional(string, null)<br/>    scope                = optional(string, null) # Defaults to storage account resource ID<br/>  }))</pre> | `[]` | no |
| shared_access_key_enabled | Whether shared access key authentication is enabled (not recommended, Entra ID authentication is preferred) | `bool` | `false` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| containers | Map of created containers with their properties |
| create | Whether resources were created |
| id | ID of the created storage account |
| name | Name of the created storage account |
| primary_access_key | Primary access key for the storage account. DEPRECATED: Use Entra ID authentication instead of access keys. |
| primary_blob_endpoint | Primary blob endpoint for the storage account |
| primary_connection_string | Primary connection string for the storage account. DEPRECATED: Use Entra ID authentication instead of connection strings. |
| private_endpoint_ids | List of private endpoint IDs if created |
| secondary_access_key | Secondary access key for the storage account. DEPRECATED: Use Entra ID authentication instead of access keys. |
| secondary_connection_string | Secondary connection string for the storage account. DEPRECATED: Use Entra ID authentication instead of connection strings. |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) — Provides standardized resource names
- [resource_group](../resource_group) — Provides the resource group to deploy into
- [networking](../networking) — Provides subnet IDs for private endpoints

## Notes

- Storage account names must be globally unique, 3-24 characters, lowercase letters and numbers only (no hyphens).
- Private endpoint is optional; set `private_endpoint.create = true` to enable.
- Shared access keys are disabled by default; Entra ID authentication is preferred.
