# Azure Storage Account Module

This Terraform module creates an Azure Storage Account with optional blob containers.

## Features

- Creates an Azure Storage Account with configurable settings
- Optionally creates blob containers within the storage account
- Configures network rules and access policies
- Supports CORS configuration for web applications
- Supports Entra ID (Azure AD) authentication with RBAC role assignments
- Applies consistent tagging

## Usage

```hcl
module "storage_account" {
  source = "../../modules/azure/storage_account"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  
  # Storage account settings
  name_components = {
    prefix      = "myapp"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }
  
  # Optional settings
  account_tier             = "Standard"
  account_replication_type = "LRS"
  
  # Container definitions (optional)
  containers = {
    "data" = {
      name                  = "data"
      container_access_type = "private"
    },
    "public" = {
      name                  = "public"
      container_access_type = "blob"
    }
  }
  
  # Disable shared access keys to enforce Entra ID authentication
  shared_access_key_enabled = false
  
  # Role assignments for Entra ID authentication
  role_assignments = [
    {
      principal_id         = "00000000-0000-0000-0000-000000000000" # Object ID of user, group, or service principal
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant Blob Data Contributor role to user"
    }
  ]
  
  # Tags
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

## Authentication

This module supports two authentication methods:

### Entra ID (Azure AD) Authentication (Recommended)

By default, the module is configured to use Entra ID authentication:

- `shared_access_key_enabled` is set to `false` by default
- Role assignments can be provided via the `role_assignments` variable
- Common roles for blob storage include:
  - "Storage Blob Data Owner" - Full access to Azure Storage blob containers and data
  - "Storage Blob Data Contributor" - Read, write, and delete access to blob containers and data
  - "Storage Blob Data Reader" - Read access to blob containers and data

### Shared Access Key Authentication (Legacy)

This method is not recommended for production use:

- Set `shared_access_key_enabled = true` to enable access keys
- Access keys are exposed in the module outputs but are marked as sensitive
- Consider using SAS tokens with limited permissions if required

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | Name of the resource group to create resources in | `string` | n/a | yes |
| location | Azure region where resources will be created | `string` | n/a | yes |
| name | Name of the storage account (if not provided, auto-generated) | `string` | `""` | no |
| name_components | Components to build the storage account name | `object` | `{}` | no |
| account_tier | Tier of the storage account (Standard or Premium) | `string` | `"Standard"` | no |
| account_replication_type | Replication type for the storage account | `string` | `"LRS"` | no |
| account_kind | Kind of storage account | `string` | `"StorageV2"` | no |
| containers | Map of containers to create | `map(object)` | `{}` | no |
| network_rules | Network rules configuration | `object` | `{}` | no |
| public_network_access_enabled | Whether public network access is allowed | `bool` | `true` | no |
| shared_access_key_enabled | Whether shared access key authentication is enabled | `bool` | `false` | no |
| private_endpoint | Private endpoint configuration | `object` | `{}` | no |
| role_assignments | List of role assignments for Entra ID auth | `list(object)` | `[]` | no |
| lifecycle_rules | Lifecycle management rules for the storage account | `list(object)` | `[]` | no |
| cors_rules | CORS rules for the storage account | `list(object)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | ID of the created storage account |
| name | Name of the created storage account |
| primary_access_key | Primary access key for the storage account (deprecated, use Entra ID instead) |
| primary_connection_string | Primary connection string for the storage account (deprecated, use Entra ID instead) |
| primary_blob_endpoint | Primary blob endpoint for the storage account |
| containers | Map of created containers with their properties |
| private_endpoint_ids | IDs of the created private endpoints |
| role_assignments | IDs of the created role assignments | 