# Azure Private DNS Zones Module

## Overview

This module creates Azure private DNS zones and links them to virtual networks. It's primarily designed for creating DNS zones needed for private endpoints and private link services, such as AKS, Storage, and Database services.

## Features

- Creates multiple private DNS zones within a resource group
- Automatically links each DNS zone to the specified virtual network
- Configurable DNS registration settings per zone
- Supports tagging for better resource organization

## Usage

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"

  resource_group_name = "networking-rg"
  
  private_dns_zones = {
    # AKS private DNS zone
    "aks" = {
      name                      = "privatelink.eastus.azmk8s.io"
      vnet_id                   = azurerm_virtual_network.main.id
      vnet_resource_group_name  = "networking-rg"
      registration_enabled      = false
      virtual_network_link_name = "link-to-main-vnet"
    },
    
    # Storage Blob private DNS zone
    "blob" = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = azurerm_virtual_network.main.id
      vnet_resource_group_name  = "networking-rg"
      registration_enabled      = false
      virtual_network_link_name = "link-to-main-vnet-blob"
    },
    
    # KeyVault private DNS zone
    "keyvault" = {
      name                      = "privatelink.vaultcore.azure.net"
      vnet_id                   = azurerm_virtual_network.main.id
      vnet_resource_group_name  = "networking-rg"
      registration_enabled      = false
      virtual_network_link_name = "link-to-main-vnet-keyvault"
    }
  }
  
  tags = {
    environment = "production"
    purpose     = "private-networking"
  }
}
```

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| resource_group_name | Name of the resource group in which to create the private DNS zones | string |
| private_dns_zones | Map of private DNS zones to create | map(object) |

The `private_dns_zones` object expects the following attributes:

| Attribute | Description |
|-----------|-------------|
| name | Name of the private DNS zone |
| vnet_id | Resource ID of the virtual network to link to |
| vnet_resource_group_name | Name of the resource group containing the virtual network |
| registration_enabled | Whether auto-registration of virtual machine DNS records is enabled |
| virtual_network_link_name | Name for the virtual network link |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| tags | Tags to apply to the resources | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| private_dns_zone_ids | Map of private DNS zone names to their IDs |

## Common Private Link DNS Zones

Here are some commonly used private link DNS zone patterns:

| Service | DNS Zone Name Pattern |
|---------|----------------------|
| AKS | privatelink.{region}.azmk8s.io |
| Blob Storage | privatelink.blob.core.windows.net |
| File Storage | privatelink.file.core.windows.net |
| Key Vault | privatelink.vaultcore.azure.net |
| SQL Server | privatelink.database.windows.net |
| PostgreSQL | privatelink.postgres.database.azure.com |
| MySQL | privatelink.mysql.database.azure.com |
| CosmosDB | privatelink.documents.azure.com |
| App Service | privatelink.azurewebsites.net |

## Notes

- Private DNS zones are regional resources but can be linked to virtual networks in any region
- Set `registration_enabled` to `false` for most private link scenarios
- For proper private endpoint operation, ensure the DNS zone name exactly matches the expected pattern for the service
- When using with Azure Private Link services, create both the zone and the private endpoint 