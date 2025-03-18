# Azure Hosting Module

This Terraform module deploys both networking and storage resources within a single Azure resource group, providing a complete hosting infrastructure for applications. It integrates these components to ensure secure network access to storage resources.

## Features

- **Standardized Naming**: Utilizes the naming module for consistent resource naming
- **Consolidated Infrastructure**: Deploy network and storage resources in a single resource group
- **Integrated Security**: Configure network access rules between VNet and storage
- **Service Endpoints**: Automatically configure service endpoints for secure storage access
- **Public/Private Access Control**: Flexible configuration of public and private storage containers
- **CORS Support**: Optional CORS configuration for web applications
- **Customer-specific Resources**: Support for both shared and customer-specific resources

## Usage

```hcl
module "hosting" {
  source = "../../modules/azure/hosting"

  # Naming module parameters (required)
  prefix      = "vip" 
  stage       = "dev"
  region_abbv = "eus"
  customer    = "contoso" # Optional, for customer-specific resources
  
  # Required parameters
  location      = "eastus"
  
  # Network configuration
  address_space = ["10.0.0.0/16"]
  subnets = {
    "app" = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "data" = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  
  # Storage account configuration
  storage_account_tier      = "Standard"
  storage_replication_type  = "LRS"
  
  # Network integration
  storage_network_default_action = "Deny"
  storage_network_bypass         = ["AzureServices"]
  storage_allowed_subnets        = ["app", "data"]
  
  # Container configuration
  storage_containers = {
    "private-data" = {
      name                  = "private-data"
      container_access_type = "private"
    },
    "public-assets" = {
      name                  = "public-assets"
      container_access_type = "blob"
    }
  }
  storage_allow_public = true
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

## Terragrunt Usage

When using Terragrunt, you can define variables in your terragrunt.hcl file:

```hcl
# terragrunt.hcl
terraform {
  source = "${get_repo_root()}/infra/modules/azure/hosting"
}

# Include environment and region configuration
include "environment" {
  path = find_in_parent_folders("env.hcl")
}

include "region" {
  path = find_in_parent_folders("region.hcl")
}

# Use locals from included files
locals {
  env_vars    = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars = read_terragrunt_config(find_in_parent_folders("region.hcl"))
}

inputs = {
  # Naming module parameters
  prefix      = "vip"
  stage       = local.env_vars.locals.environment
  region_abbv = local.region_vars.locals.region_abbv
  customer    = local.env_vars.locals.customer # Optional
  
  # Required parameters
  location      = local.region_vars.locals.azure_region
  
  # Network configuration
  address_space = ["10.0.0.0/16"]
  subnets = {
    "app" = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "data" = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  
  # Storage account configuration
  storage_account_tier      = "Standard"
  storage_replication_type  = "LRS"
  
  # Network integration
  storage_network_default_action = "Deny"
  storage_network_bypass         = ["AzureServices"]
  storage_allowed_subnets        = ["app", "data"]
  
  # Container configuration - create both private and public containers
  storage_containers = {
    "private-data" = {
      name                  = "private-data"
      container_access_type = "private"
    },
    "public-assets" = {
      name                  = "public-assets"
      container_access_type = "blob"
    }
  }
  
  # Allow public access for the public container
  storage_allow_public = true
  
  tags = {
    Environment = local.env_vars.locals.environment
    ManagedBy   = "Terragrunt"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| prefix | Prefix to use for resource naming (usually 'vip') | `string` | `"vip"` | no |
| customer | Customer name to use in resource naming (optional for shared resources) | `string` | `null` | no |
| stage | Environment stage (dev, test, prod, etc.) | `string` | n/a | yes |
| region_abbv | Abbreviated Azure region name (e.g., eus, wus, etc.) | `string` | n/a | yes |
| location | Azure region where resources will be deployed | `string` | n/a | yes |
| address_space | Address space for the virtual network | `list(string)` | n/a | yes |
| subnets | Map of subnet configurations | `map(object)` | n/a | yes |
| dns_servers | List of DNS servers to use with the virtual network | `list(string)` | `[]` | no |
| storage_account_tier | Tier of storage account to create | `string` | `"Standard"` | no |
| storage_replication_type | Replication type for the storage account | `string` | `"LRS"` | no |
| storage_network_default_action | Default action for storage network rules | `string` | `"Deny"` | no |
| storage_network_bypass | List of services to bypass storage network rules | `list(string)` | `["AzureServices"]` | no |
| storage_allowed_subnets | List of subnet names from the network module that can access storage | `list(string)` | `[]` | no |
| storage_containers | Map of containers to create in the storage account | `map(object)` | `{}` | no |
| storage_allow_public | Whether to allow public access to storage containers | `bool` | `false` | no |
| storage_cors_rules | CORS rules for the storage account blob service | `list(object)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| resource_group_name | *DEPRECATED*: Name is now derived from the naming module | `string` | `null` | no |
| vnet_name | *DEPRECATED*: Name is now derived from the naming module | `string` | `null` | no |
| storage_name_components | *DEPRECATED*: Storage account name is now derived from the naming module | `object` | `{}` | no |
| storage_account_name | *DEPRECATED*: Storage account name is now derived from the naming module | `string` | `null` | no |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | The name of the resource group |
| resource_group_id | The ID of the resource group |
| vnet_id | The ID of the virtual network |
| vnet_name | The name of the virtual network |
| subnet_ids | Map of subnet names to IDs |
| storage_account_name | The name of the storage account |
| storage_account_id | The ID of the storage account |
| primary_blob_endpoint | The primary blob endpoint URL |
| containers | Map of created containers with their properties |
| naming | Resource name outputs from the naming module |

## Naming Module Integration

The hosting module always uses the [naming module](../naming) to generate standardized resource names. This ensures consistency across all resources following platform naming conventions.

- **Resource Group:** `vip-{customer}-{stage}-rg-{region_abbv}`
- **Virtual Network:** `vip-{customer}-{stage}-vnet-{region_abbv}`
- **Storage Account:** `vip{customer}{stage}sa{region_abbv}`
- **Subnets:** `vip-{customer}-{stage}-subnet-{subnet_type}-{region_abbv}`

For shared resources where no customer is specified, the customer segment is omitted:
- **Resource Group:** `vip-{stage}-rg-{region_abbv}`
- **Virtual Network:** `vip-{stage}-vnet-{region_abbv}`

## Components

This module combines and integrates these individual modules:
- [naming](../naming): Provides standardized resource naming
- [networking](../networking): Creates the virtual network and subnets
- [storage_account](../storage_account): Creates the storage account with containers

## License

This module is licensed under the MIT License - see the LICENSE file for details. 