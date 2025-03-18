# Azure Storage Account Module

This Terraform module creates an Azure Storage Account with optional blob containers.

## Features

- Creates an Azure Storage Account with configurable settings
- Optionally creates blob containers within the storage account
- Configures network rules and access policies
- Supports CORS configuration for web applications
- Applies consistent tagging

## Usage

```hcl
module "storage_account" {
  source = "../../modules/azure/storage_account"

  resource_group_name = "my-resource-group"
  location            = "eastus"
  
  # Storage account settings
  storage_name_components = {
    prefix      = "myapp"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }
  
  # Optional settings
  storage_account_tier     = "Standard"
  storage_replication_type = "LRS"
  
  # Container definitions (optional)
  storage_containers = {
    "data" = {
      name                  = "data"
      container_access_type = "private"
    },
    "public" = {
      name                  = "public"
      container_access_type = "blob"
    }
  }
  
  # Tags
  tags = {
    Environment = "Development"
    Project     = "MyProject"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | Name of the resource group to create resources in | `string` | n/a | yes |
| location | Azure region where resources will be created | `string` | n/a | yes |
| storage_name_components | Components to build the storage account name | `object` | n/a | yes |
| storage_account_tier | Tier of the storage account (Standard or Premium) | `string` | `"Standard"` | no |
| storage_replication_type | Replication type for the storage account | `string` | `"LRS"` | no |
| storage_containers | Map of containers to create | `map(object)` | `{}` | no |
| storage_network_default_action | Default action for network rules (Allow or Deny) | `string` | `"Deny"` | no |
| storage_network_bypass | Network services to bypass restrictions | `list(string)` | `["AzureServices"]` | no |
| storage_allow_public | Allow public access to the storage account | `bool` | `false` | no |
| storage_allowed_ips | List of IP addresses to allow access | `list(string)` | `[]` | no |
| storage_allowed_subnets | List of subnet names to allow access | `list(string)` | `[]` | no |
| storage_cors_rules | CORS rules for the storage account | `list(object)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| storage_account_id | ID of the created storage account |
| storage_account_name | Name of the created storage account |
| storage_primary_access_key | Primary access key for the storage account |
| storage_primary_connection_string | Primary connection string for the storage account |
| storage_primary_blob_endpoint | Primary blob endpoint for the storage account |
| storage_containers | Map of created containers with their properties | 