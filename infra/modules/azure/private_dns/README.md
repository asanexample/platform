# Private DNS

Creates Azure private DNS zones and links them to virtual networks. Each DNS zone is defined as a map entry with its domain name, target VNet, and registration settings. VNet links enable DNS resolution for private endpoints and other resources within the linked virtual network. This module handles the common pattern of creating multiple private DNS zones (e.g., for Key Vault, Storage, AKS) and linking them all to the same VNet.

## Usage

```hcl
module "private_dns" {
  source = "../../modules/azure/private_dns"

  resource_group_name = "rg-platform-dev-eus"

  private_dns_zones = {
    "keyvault" = {
      name                      = "privatelink.vaultcore.azure.net"
      vnet_id                   = "/subscriptions/.../virtualNetworks/vnet-platform-dev-eus"
      vnet_resource_group_name  = "rg-platform-dev-eus"
      registration_enabled      = false
      virtual_network_link_name = "keyvault-vnet-link"
    }
    "blob" = {
      name                      = "privatelink.blob.core.windows.net"
      vnet_id                   = "/subscriptions/.../virtualNetworks/vnet-platform-dev-eus"
      vnet_resource_group_name  = "rg-platform-dev-eus"
      registration_enabled      = false
      virtual_network_link_name = "blob-vnet-link"
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
module "private_dns" {
  source = "../../modules/azure/private_dns"
  create = false
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
| [azurerm_private_dns_zone.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_private_dns_zones"></a> [private\_dns\_zones](#input\_private\_dns\_zones) | Map of private DNS zones to create | <pre>map(object({<br/>    name                      = string<br/>    vnet_id                   = string<br/>    vnet_resource_group_name  = string<br/>    registration_enabled      = bool<br/>    virtual_network_link_name = string<br/>  }))</pre> | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group in which to create the private DNS zones | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_private_dns_zone_ids"></a> [private\_dns\_zone\_ids](#output\_private\_dns\_zone\_ids) | Map of private DNS zone names to their IDs |
<!-- END_TF_DOCS -->

## Notes

- Set `registration_enabled = true` to enable auto-registration of VM DNS records in the zone. This is typically only needed for custom private DNS zones, not Azure service privatelink zones.
- DNS zone names must be valid domain names using lowercase letters, numbers, hyphens, and periods.
- The output `private_dns_zone_ids` is a map keyed by the input map keys, which can be passed to private endpoint configurations in other modules (e.g., `key_vault`, `storage_account`).
