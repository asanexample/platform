# Azure Storage Account Module

## Overview

This module creates an Azure Storage Account with configurable settings, optional blob containers, and robust security controls. It supports modern authentication methods, network access controls, and follows Azure best practices for storage management.

## Features

- Creates an Azure Storage Account with configurable settings
- Optionally creates blob containers within the storage account
- Configures network rules and access policies
- Supports CORS configuration for web applications
- Supports Entra ID (Azure AD) authentication with RBAC role assignments
- Enforces secure defaults with modern authentication methods
- Applies consistent tagging

## Usage

```hcl
module "storage_account" {
  source = "../../modules/azure/storage_account"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
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
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Basic Storage Account

```hcl
module "basic_storage" {
  source = "../../modules/azure/storage_account"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name_components = {
    prefix      = "basic"
    environment = "dev"
    region_abbv = "eus"
  }
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Production Storage with Enhanced Security

```hcl
module "secure_storage" {
  source = "../../modules/azure/storage_account"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name = "securestorageprod"
  
  account_tier             = "Standard"
  account_replication_type = "GRS"
  account_kind             = "StorageV2"
  
  # Enforce HTTPS and latest TLS version
  min_tls_version             = "TLS1_2"
  enable_https_traffic_only   = true
  
  # Disable public network access
  public_network_access_enabled = false
  
  # Disable shared access keys
  shared_access_key_enabled = false
  
  # Configure private endpoint
  private_endpoint = {
    subnet_id          = module.networking.subnet_ids["endpoints"]
    private_dns_zone_id = module.private_dns.zone_ids["privatelink.blob.core.windows.net"]
  }
  
  # Define lifecycle rules for cost optimization
  lifecycle_rules = [
    {
      name    = "archive-after-90-days"
      enabled = true
      base_blob = {
        tier_to_archive_after_days = 90
        delete_after_days          = 365
      }
    }
  ]
  
  tags = {
    Environment        = "Production"
    ManagedBy          = "Terraform"
    DataClassification = "Confidential"
    CostCenter         = "IT-12345"
  }
}
```

### Web Application Storage with CORS

```hcl
module "webapp_storage" {
  source = "../../modules/azure/storage_account"

  resource_group_name = module.resource_group.name
  location            = module.resource_group.location
  
  name_components = {
    prefix      = "webapp"
    environment = "prod"
    region_abbv = "eus"
  }
  
  account_tier             = "Standard"
  account_replication_type = "ZRS"
  
  containers = {
    "assets" = {
      name                  = "assets"
      container_access_type = "blob"
    },
    "uploads" = {
      name                  = "uploads"
      container_access_type = "private"
    }
  }
  
  # Configure CORS for web access
  cors_rules = [
    {
      allowed_origins    = ["https://mywebapp.com", "https://www.mywebapp.com"]
      allowed_methods    = ["GET", "PUT", "POST"]
      allowed_headers    = ["*"]
      exposed_headers    = ["Content-Length", "Content-Type"]
      max_age_in_seconds = 3600
    }
  ]
  
  # Network rules to restrict access
  network_rules = {
    default_action = "Deny"
    ip_rules       = ["203.0.113.0/24"]
    virtual_network_subnet_ids = [module.networking.subnet_ids["web"]]
    bypass         = ["AzureServices"]
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Application = "WebApp"
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
| resource_group_name | Name of the resource group to create resources in | `string` |
| location | Azure region where resources will be created | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
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

## Module Resources

This module creates the following resources:
- Azure Storage Account
- Storage Containers (optional)
- Private Endpoints (optional)
- Role Assignments for RBAC (optional)

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation
- [networking](../networking) - For private endpoint subnet references
- [private_dns](../private_dns) - For private endpoint DNS zone integration

## Authentication Methods

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

## Security Best Practices

For production deployments, consider implementing the following security measures:

1. **Use Entra ID Authentication** - Disable shared access keys and use RBAC
2. **Implement Network Restrictions** - Use private endpoints or network rules
3. **Enable Encryption** - Use customer-managed keys for enhanced control
4. **Configure Lifecycle Management** - Implement tiering and retention policies
5. **Implement Monitoring** - Enable diagnostic settings and alerts
6. **Enforce TLS 1.2+** - Require secure connections with modern TLS

## Notes

- Storage account names must be globally unique across all of Azure
- The auto-generated name follows the pattern `{prefix}{environment}{region_abbv}{instance}`
- For production environments, consider using geo-redundant storage (GRS or GZRS)
- Use lifecycle management policies to optimize storage costs
- Private endpoints are recommended for production environments
- Role assignments require proper permissions for the deploying identity

## License

This module is licensed under the MIT License. 