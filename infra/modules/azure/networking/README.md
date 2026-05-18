# Azure Networking Module

Creates a VNet with subnets, NSGs, and AKS-specific networking features for secure, scalable cloud infrastructure.

## Usage

```hcl
module "networking" {
  source = "../networking"

  create = true

  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"
  vnet_name           = "vnet-platform-prod-eus"
  address_space       = ["10.0.0.0/16"]

  subnets = {
    "az1-nodes" = {
      address_prefixes = ["10.0.0.0/24"]
    }
    "az2-nodes" = {
      address_prefixes = ["10.0.1.0/24"]
    }
    "az3-nodes" = {
      address_prefixes = ["10.0.2.0/24"]
    }
    "endpoints" = {
      address_prefixes  = ["10.0.10.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
  }

  enable_aks_networking = true
  aks_subnet_name       = "az1-nodes"
  aks_cluster_name      = "aks-platform-prod-eus"

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "networking" {
  source = "../networking"
  create = false
}
```

### Minimal VNet without AKS

```hcl
module "networking" {
  source = "../networking"

  create = true

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  vnet_name           = "vnet-platform-dev-eus"
  address_space       = ["10.1.0.0/16"]

  subnets = {
    "workloads" = {
      address_prefixes = ["10.1.0.0/22"]
    }
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Cross-Cloud Interface

This module exposes cloud-agnostic outputs so downstream modules can consume networking regardless of provider.

| Output | Description |
|--------|-------------|
| `network_id` | VNet ID |
| `network_name` | VNet name |
| `subnet_ids` | Map of subnet name to subnet ID |
| `kubernetes_subnet_id` | AKS node subnet ID |
| `create` | Whether resources were created |

<!-- BEGIN_TF_DOCS -->
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
| location | Azure region where resources will be deployed | `string` | n/a | yes |
| resource_group_name | Name of the resource group to deploy the virtual network in | `string` | n/a | yes |
| vnet_name | Name of the virtual network to create | `string` | n/a | yes |
| address_space | Address space for the virtual network | `list(string)` | <pre>[<br/>  "10.0.0.0/16"<br/>]</pre> | no |
| aks_cluster_name | Name of the AKS cluster. Required if enable_aks_networking is true. | `string` | `null` | no |
| aks_node_resource_group | Name of the resource group where AKS will create node resources | `string` | `null` | no |
| aks_private_cluster_enabled | Whether the AKS cluster is private. This affects DNS zone creation. | `bool` | `false` | no |
| aks_private_dns_zone_id | ID of an existing private DNS zone for AKS. If not provided, a new one will be created if needed. | `string` | `null` | no |
| aks_subnet_name | Name of the subnet to use for AKS nodes. Must match a key in the subnets map. | `string` | `null` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| dns_servers | List of DNS servers to use with the virtual network | `list(string)` | `[]` | no |
| enable_aks_networking | Whether to enable AKS-specific networking features | `bool` | `false` | no |
| subnets | Map of subnet names to configuration | <pre>map(object({<br/>    address_prefixes  = list(string)<br/>    service_endpoints = optional(list(string), [])<br/>    delegation        = optional(map(list(map(string))), {})<br/>  }))</pre> | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| aks_nsg_id | The ID of the network security group attached to the AKS subnet |
| aks_private_dns_zone_id | The ID of the AKS private DNS zone if created |
| aks_private_dns_zone_name | The name of the AKS private DNS zone if created |
| aks_subnet_id | The ID of the subnet used for AKS nodes |
| create | Whether resources were created |
| kubernetes_subnet_id | Cloud-agnostic subnet ID for Kubernetes nodes |
| network_id | Cloud-agnostic network identifier (VNet ID on Azure, VPC ID on AWS) |
| network_name | Cloud-agnostic network name |
| nsg_ids | Map of subnet names to network security group IDs |
| private_endpoints_subnet_id | The ID of the private endpoints subnet if it exists |
| subnet_ids | Map of subnet names to subnet IDs |
| vnet_address_space | The address space of the virtual network |
| vnet_id | The ID of the virtual network |
| vnet_location | The location of the virtual network |
| vnet_name | The name of the virtual network |
| vnet_resource_group_name | The name of the resource group containing the virtual network |
| vnet_subnet_ids | List of all subnet IDs in the virtual network |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) — Provides standardized resource names
- [resource_group](../resource_group) — Provides the resource group to deploy into

## Notes

- `AzureFirewallSubnet` is excluded from NSG associations (Azure requirement).
- For Cilium CNI, smaller subnets can be used since pod IPs are managed by Cilium, not Azure CNI IPAM.
