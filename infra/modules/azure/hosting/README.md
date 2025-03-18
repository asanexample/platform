# Azure Hosting Module

This Terraform module deploys both networking and storage resources within a single Azure resource group, providing a complete hosting infrastructure for applications. It integrates these components to ensure secure network access to storage resources.

## Features

- **Consolidated Infrastructure**: Deploy network and storage resources in a single resource group
- **Integrated Security**: Configure network access rules between VNet and storage
- **Service Endpoints**: Automatically configure service endpoints for secure storage access
- **Public/Private Access Control**: Flexible configuration of public and private storage containers
- **CORS Support**: Optional CORS configuration for web applications

## Usage

```hcl
module "hosting" {
  source = "../../modules/azure/hosting"

  # Resource group configuration
  resource_group_name = "app-hosting-rg"
  location            = "eastus"
  
  # Network configuration
  vnet_name     = "app-network"
  address_space = ["10.0.0.0/16"]
  subnets = {
    "app-subnet" = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "data-subnet" = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  
  # Storage account configuration
  storage_name_components = {
    prefix      = "app"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }
  storage_account_tier      = "Standard"
  storage_replication_type  = "LRS"
  
  # Network integration
  storage_network_default_action = "Deny"
  storage_network_bypass         = ["AzureServices"]
  storage_allowed_subnets        = ["app-subnet", "data-subnet"]
  
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

inputs = {
  # Resource group
  resource_group_name = "app-hosting-rg"
  location            = "eastus"
  
  # Network configuration
  vnet_name     = "app-network"
  address_space = ["10.0.0.0/16"]
  subnets = {
    "app-subnet" = {
      address_prefixes  = ["10.0.1.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    },
    "data-subnet" = {
      address_prefixes  = ["10.0.2.0/24"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  
  # Storage account configuration
  storage_name_components = {
    prefix      = "app"
    environment = "dev"
    region_abbv = "eus"
    instance    = "001"
  }
  storage_account_tier      = "Standard"
  storage_replication_type  = "LRS"
  
  # Network integration
  storage_network_default_action = "Deny"
  storage_network_bypass         = ["AzureServices"]
  storage_allowed_subnets        = ["app-subnet", "data-subnet"]
  
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
    Environment = "Development"
    ManagedBy   = "Terragrunt"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| resource_group_name | Name of the resource group to deploy resources in | `string` | n/a | yes |
| location | Azure region where resources will be deployed | `string` | n/a | yes |
| vnet_name | Name of the virtual network | `string` | n/a | yes |
| address_space | Address space for the virtual network | `list(string)` | n/a | yes |
| subnets | Map of subnet configurations | `map(object)` | n/a | yes |
| dns_servers | List of DNS servers to use with the virtual network | `list(string)` | `[]` | no |
| storage_name_components | Components to auto-generate the storage account name | `object` | `{}` | no |
| storage_account_tier | Tier of storage account to create | `string` | `"Standard"` | no |
| storage_replication_type | Replication type for the storage account | `string` | `"LRS"` | no |
| storage_network_default_action | Default action for storage network rules | `string` | `"Deny"` | no |
| storage_network_bypass | List of services to bypass storage network rules | `list(string)` | `["AzureServices"]` | no |
| storage_allowed_subnets | List of subnet names from the network module that can access storage | `list(string)` | `[]` | no |
| storage_containers | Map of containers to create in the storage account | `map(object)` | `{}` | no |
| storage_allow_public | Whether to allow public access to storage containers | `bool` | `false` | no |
| storage_cors_rules | CORS rules for the storage account blob service | `list(object)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| resource_group_name | The name of the resource group |
| resource_group_id | The ID of the resource group |
| vnet_id | The ID of the virtual network |
| vnet_name | The name of the virtual network |
| subnet_ids | Map of subnet names to IDs |
| nsg_ids | Map of subnet names to network security group IDs |
| storage_account_name | The name of the storage account |
| storage_account_id | The ID of the storage account |
| storage_primary_access_key | The primary access key for the storage account |
| storage_primary_connection_string | The primary connection string for the storage account |
| storage_primary_blob_endpoint | The primary blob endpoint URL |
| storage_containers | Map of created containers with their properties |

## Notes

- The module automatically connects subnets to storage accounts using service endpoints
- Storage account network rules are configured to allow only the specified subnets
- Public access for storage containers is controlled by the `storage_allow_public` variable
- When `storage_allow_public` is set to false, all containers will be private regardless of container access type

## Components

This module combines and integrates these individual modules:
- [networking](../networking): Creates the virtual network and subnets
- [storage_account](../storage_account): Creates the storage account with containers

## License

This module is licensed under the MIT License - see the LICENSE file for details. 