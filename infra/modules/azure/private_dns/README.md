# Azure Private DNS Module

Creates private DNS zones and links them to a virtual network for private endpoint name resolution.

## Usage

```hcl
module "private_dns" {
  source = "../private_dns"

  create = true

  resource_group_name = "rg-platform-prod-eus"

  private_dns_zones = {
    "blob" = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = "rg-platform-prod-eus"
      registration_enabled      = false
      virtual_network_link_name = "link-to-prod-vnet-blob"
    }
    "keyvault" = {
      name                      = "privatelink.vaultcore.azure.net"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = "rg-platform-prod-eus"
      registration_enabled      = false
      virtual_network_link_name = "link-to-prod-vnet-keyvault"
    }
    "aks" = {
      name                      = "privatelink.eastus.azmk8s.io"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = "rg-platform-prod-eus"
      registration_enabled      = false
      virtual_network_link_name = "link-to-prod-vnet-aks"
    }
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
module "private_dns" {
  source = "../private_dns"
  create = false
}
```

### Single zone

```hcl
module "private_dns" {
  source = "../private_dns"

  create = true

  resource_group_name = "rg-platform-dev-eus"

  private_dns_zones = {
    "blob" = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = module.networking.id
      vnet_resource_group_name  = "rg-platform-dev-eus"
      registration_enabled      = false
      virtual_network_link_name = "link-to-dev-vnet-blob"
    }
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
| [azurerm_private_dns_zone.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| private_dns_zones | Map of private DNS zones to create | <pre>map(object({<br/>    name                      = string<br/>    vnet_id                   = string<br/>    vnet_resource_group_name  = string<br/>    registration_enabled      = bool<br/>    virtual_network_link_name = string<br/>  }))</pre> | n/a | yes |
| resource_group_name | The name of the resource group in which to create the private DNS zones | `string` | n/a | yes |
| create | Whether to create resources in this module | `bool` | `true` | no |
| tags | A mapping of tags to assign to the resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| private_dns_zone_ids | Map of private DNS zone names to their IDs |
<!-- END_TF_DOCS -->

## Dependencies

- [networking](../networking) — Provides the VNet ID to link zones to
- [resource_group](../resource_group) — Provides the resource group to deploy into

## Notes

- Set `registration_enabled = false` for private link zones (the typical case). Auto-registration is only for VM DNS records.
- DNS zone names must exactly match the expected pattern for each Azure service (e.g., `privatelink.blob.core.windows.net`).
- AKS private DNS zones are region-specific: `privatelink.{region}.azmk8s.io`.
