# Networking

Creates an Azure Virtual Network with subnets, network security groups (NSGs), and NSG-to-subnet associations. When AKS networking is enabled, the module adds Cilium-specific NSG rules (VXLAN port 8472, health check port 4240, node-to-node communication) and optionally creates a private DNS zone for private AKS clusters with VNet linking. Each subnet gets its own NSG, except `AzureFirewallSubnet` which is excluded from NSG association per Azure requirements. The module also exposes cloud-agnostic outputs (`network_id`, `kubernetes_subnet_id`) for consumption by cross-cloud modules like Cilium and ArgoCD.

## Usage

```hcl
module "networking" {
  source = "../../modules/azure/networking"

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  vnet_name           = "vnet-platform-dev-eus"
  address_space       = ["10.200.0.0/16"]

  subnets = {
    "snet-platform-dev-node-eus" = {
      address_prefixes  = ["10.200.0.0/20"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    "snet-platform-dev-endpoint-eus" = {
      address_prefixes = ["10.200.16.0/24"]
    }
  }

  enable_aks_networking = true
  aks_subnet_name       = "snet-platform-dev-node-eus"
  aks_cluster_name      = "aks-platform-dev-eus"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "networking" {
  source = "../../modules/azure/networking"
  create = false
}
```

### Private AKS Cluster with DNS Zone

```hcl
module "networking" {
  source = "../../modules/azure/networking"

  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"
  vnet_name           = "vnet-platform-prod-eus"
  address_space       = ["10.200.0.0/16"]

  subnets = {
    "snet-platform-prod-node-eus" = {
      address_prefixes = ["10.200.0.0/20"]
    }
  }

  enable_aks_networking       = true
  aks_subnet_name             = "snet-platform-prod-node-eus"
  aks_cluster_name            = "aks-platform-prod-eus"
  aks_private_cluster_enabled = true
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
| [azurerm_network_security_group.nsg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_group) | resource |
| [azurerm_network_security_rule.aks_allow_cilium_health](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_network_security_rule.aks_allow_lb](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_network_security_rule.aks_allow_node_communication](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_network_security_rule.aks_allow_vxlan](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_network_security_rule.aks_deny_inbound](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/network_security_rule) | resource |
| [azurerm_private_dns_zone.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone) | resource |
| [azurerm_private_dns_zone_virtual_network_link.aks](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/private_dns_zone_virtual_network_link) | resource |
| [azurerm_subnet.subnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet) | resource |
| [azurerm_subnet_network_security_group_association.nsg_association](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/subnet_network_security_group_association) | resource |
| [azurerm_virtual_network.vnet](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/virtual_network) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region where resources will be deployed | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group to deploy the virtual network in | `string` | n/a | yes |
| <a name="input_vnet_name"></a> [vnet\_name](#input\_vnet\_name) | Name of the virtual network to create | `string` | n/a | yes |
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | Address space for the virtual network | `list(string)` | <pre>[<br/>  "10.0.0.0/16"<br/>]</pre> | no |
| <a name="input_aks_cluster_name"></a> [aks\_cluster\_name](#input\_aks\_cluster\_name) | Name of the AKS cluster. Required if enable\_aks\_networking is true. | `string` | `null` | no |
| <a name="input_aks_node_resource_group"></a> [aks\_node\_resource\_group](#input\_aks\_node\_resource\_group) | Name of the resource group where AKS will create node resources | `string` | `null` | no |
| <a name="input_aks_private_cluster_enabled"></a> [aks\_private\_cluster\_enabled](#input\_aks\_private\_cluster\_enabled) | Whether the AKS cluster is private. This affects DNS zone creation. | `bool` | `false` | no |
| <a name="input_aks_private_dns_zone_id"></a> [aks\_private\_dns\_zone\_id](#input\_aks\_private\_dns\_zone\_id) | ID of an existing private DNS zone for AKS. If not provided, a new one will be created if needed. | `string` | `null` | no |
| <a name="input_aks_subnet_name"></a> [aks\_subnet\_name](#input\_aks\_subnet\_name) | Name of the subnet to use for AKS nodes. Must match a key in the subnets map. | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_dns_servers"></a> [dns\_servers](#input\_dns\_servers) | List of DNS servers to use with the virtual network | `list(string)` | `[]` | no |
| <a name="input_enable_aks_networking"></a> [enable\_aks\_networking](#input\_enable\_aks\_networking) | Whether to enable AKS-specific networking features | `bool` | `false` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Map of subnet names to configuration | <pre>map(object({<br/>    address_prefixes  = list(string)<br/>    service_endpoints = optional(list(string), [])<br/>    delegation        = optional(map(list(map(string))), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_aks_nsg_id"></a> [aks\_nsg\_id](#output\_aks\_nsg\_id) | The ID of the network security group attached to the AKS subnet |
| <a name="output_aks_private_dns_zone_id"></a> [aks\_private\_dns\_zone\_id](#output\_aks\_private\_dns\_zone\_id) | The ID of the AKS private DNS zone if created |
| <a name="output_aks_private_dns_zone_name"></a> [aks\_private\_dns\_zone\_name](#output\_aks\_private\_dns\_zone\_name) | The name of the AKS private DNS zone if created |
| <a name="output_aks_subnet_id"></a> [aks\_subnet\_id](#output\_aks\_subnet\_id) | The ID of the subnet used for AKS nodes |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_kubernetes_subnet_id"></a> [kubernetes\_subnet\_id](#output\_kubernetes\_subnet\_id) | Cloud-agnostic subnet ID for Kubernetes nodes |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | Cloud-agnostic network identifier (VNet ID on Azure, VPC ID on AWS) |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Cloud-agnostic network name |
| <a name="output_nsg_ids"></a> [nsg\_ids](#output\_nsg\_ids) | Map of subnet names to network security group IDs |
| <a name="output_private_endpoints_subnet_id"></a> [private\_endpoints\_subnet\_id](#output\_private\_endpoints\_subnet\_id) | The ID of the private endpoints subnet if it exists |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Map of subnet names to subnet IDs |
| <a name="output_vnet_address_space"></a> [vnet\_address\_space](#output\_vnet\_address\_space) | The address space of the virtual network |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | The ID of the virtual network |
| <a name="output_vnet_location"></a> [vnet\_location](#output\_vnet\_location) | The location of the virtual network |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | The name of the virtual network |
| <a name="output_vnet_resource_group_name"></a> [vnet\_resource\_group\_name](#output\_vnet\_resource\_group\_name) | The name of the resource group containing the virtual network |
| <a name="output_vnet_subnet_ids"></a> [vnet\_subnet\_ids](#output\_vnet\_subnet\_ids) | List of all subnet IDs in the virtual network |
<!-- END_TF_DOCS -->

## Notes

- When `enable_aks_networking = true`, the module adds NSG rules for Cilium VXLAN (UDP 8472), Cilium health (TCP 4240), Azure Load Balancer, and inter-node communication on the AKS subnet.
- A deny-all inbound rule is added at priority 4096 on the AKS subnet NSG. All allowed traffic must have explicit rules with lower priority numbers.
- If `aks_private_cluster_enabled = true` and no `aks_private_dns_zone_id` is provided, a private DNS zone (`privatelink.{region}.azmk8s.io`) is created and linked to the VNet.
- The `AzureFirewallSubnet` name is treated specially -- it is excluded from NSG associations, as Azure does not allow NSGs on firewall subnets.
