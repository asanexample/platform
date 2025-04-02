# Azure Private DNS Zones Module

## Overview

This module creates Azure Private DNS Zones and links them to virtual networks. It enables private name resolution for Azure services using Private Link and Private Endpoints, providing a secure DNS resolution solution for hybrid cloud environments.

## Features

- Creates multiple private DNS zones within a resource group
- Automatically links each DNS zone to the specified virtual network
- Configures DNS registration settings per zone
- Supports common private link services patterns
- Implements secure network integration for private endpoints
- Applies consistent tagging for better resource management

## Usage

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"

  resource_group_name = module.resource_group.name
  
  private_dns_zones = {
    # AKS private DNS zone
    "aks" = {
      name                      = "privatelink.eastus.azmk8s.io"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = module.resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-main-vnet"
    },
    
    # Storage Blob private DNS zone
    "blob" = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = module.resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-main-vnet-blob"
    },
    
    # KeyVault private DNS zone
    "keyvault" = {
      name                      = "privatelink.vaultcore.azure.net"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = module.resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-main-vnet-keyvault"
    }
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Networking"
  }
}
```

## Examples

### Basic Private DNS Setup

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"

  resource_group_name = module.resource_group.name
  
  private_dns_zones = {
    "sql" = {
      name                      = "privatelink.database.windows.net"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = module.resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-main-vnet-sql"
    }
  }
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Multiple Services with Centralized DNS

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"

  resource_group_name = module.dns_resource_group.name
  
  private_dns_zones = {
    "aks" = {
      name                      = "privatelink.eastus.azmk8s.io"
      vnet_id                   = module.hub_networking.id
      vnet_resource_group_name  = module.hub_resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-hub-vnet"
    },
    "blob" = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = module.hub_networking.id
      vnet_resource_group_name  = module.hub_resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-hub-vnet-blob"
    },
    "keyvault" = {
      name                      = "privatelink.vaultcore.azure.net"
      vnet_id                   = module.hub_networking.id
      vnet_resource_group_name  = module.hub_resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-hub-vnet-keyvault"
    },
    "postgres" = {
      name                      = "privatelink.postgres.database.azure.com"
      vnet_id                   = module.hub_networking.id
      vnet_resource_group_name  = module.hub_resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-hub-vnet-postgres"
    }
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "DNS"
  }
}
```

### Hub and Spoke DNS Configuration

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"

  resource_group_name = module.hub_resource_group.name
  
  private_dns_zones = {
    "aks" = {
      name                      = "privatelink.eastus.azmk8s.io"
      vnet_id                   = module.hub_networking.id
      vnet_resource_group_name  = module.hub_resource_group.name
      registration_enabled      = false
      virtual_network_link_name = "link-to-hub-vnet"
    }
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
  }
}

# Add links to spoke virtual networks
resource "azurerm_private_dns_zone_virtual_network_link" "spoke1" {
  name                  = "link-to-spoke1-vnet"
  resource_group_name   = module.hub_resource_group.name
  private_dns_zone_name = module.private_dns.private_dns_zone_ids["aks"]
  virtual_network_id    = module.spoke1_networking.id
  registration_enabled  = false
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
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
| resource_group_name | Name of the resource group in which to create the private DNS zones | `string` |
| private_dns_zones | Map of private DNS zones to create | `map(object)` |

### Private DNS Zone Object

The `private_dns_zones` object expects the following attributes:

| Attribute | Description | Type | Required |
|-----------|-------------|------|:--------:|
| name | Name of the private DNS zone | `string` | yes |
| vnet_id | Resource ID of the virtual network to link to | `string` | yes |
| vnet_resource_group_name | Name of the resource group containing the virtual network | `string` | yes |
| registration_enabled | Whether auto-registration of virtual machine DNS records is enabled | `bool` | yes |
| virtual_network_link_name | Name for the virtual network link | `string` | yes |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| tags | Tags to apply to the resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| private_dns_zone_ids | Map of private DNS zone names to their IDs |

## Module Resources

This module creates the following resources:
- Azure Private DNS Zones
- Azure Private DNS Zone Virtual Network Links

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation
- [networking](../networking) - For virtual network ID references

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
| Event Hub | privatelink.servicebus.windows.net |
| Container Registry | privatelink.azurecr.io |
| Cognitive Services | privatelink.cognitiveservices.azure.com |

## Private DNS Architecture

### Single Virtual Network

For single virtual network environments, link each private DNS zone directly to the virtual network where your services are deployed.

### Hub and Spoke Model

In hub and spoke architectures, consider the following practices:
1. Create private DNS zones in a centralized resource group, typically in the hub
2. Link the zones to the hub virtual network with this module
3. Create additional virtual network links to each spoke virtual network
4. Use `registration_enabled = false` for private link DNS zones

### Global DNS Resolution

For multi-region deployments:
1. Create region-specific DNS zones for regional services (e.g., AKS)
2. Use global DNS zones for global services (e.g., storage, key vault)
3. Link all zones to all virtual networks that need DNS resolution

## Notes

- Private DNS zones are global resources but contain region-specific naming patterns for regional services
- Set `registration_enabled` to `false` for most private link scenarios
- For proper private endpoint operation, ensure the DNS zone name exactly matches the expected pattern for the service
- When using with Azure Private Link services, create both the zone and the private endpoint
- Consider DNS resolution needs when working with hybrid environments connecting to on-premises networks
- If using Azure Firewall for DNS, ensure proxy settings are configured correctly

## License

This module is licensed under the MIT License. 