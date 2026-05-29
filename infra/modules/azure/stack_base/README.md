# Stack Base

Composite module that wires together `resource_group`, `networking`, and `key_vault` into a single deployable base infrastructure unit. This demonstrates the composite module pattern: small single-purpose modules composed with explicit dependencies. Deploying this module provisions a resource group, a VNet with subnets and NSGs, and optionally a Key Vault -- the foundational layer for any Azure environment. It also exposes cloud-agnostic outputs (`network_id`, `kubernetes_subnet_id`) for cross-cloud module compatibility.

## Usage

```hcl
module "stack_base" {
  source = "../../modules/azure/stack_base"

  name        = "rg-platform-dev-eus"
  location    = "eastus"
  environment = "dev"
  workload    = "platform"
  region_abbv = "eus"

  address_space = ["10.200.0.0/16"]

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

  enable_key_vault = true
  key_vault_sku    = "standard"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "stack_base" {
  source = "../../modules/azure/stack_base"
  create = false
}
```

### Without Key Vault

```hcl
module "stack_base" {
  source = "../../modules/azure/stack_base"

  name             = "rg-platform-dev-eus"
  location         = "eastus"
  environment      = "dev"
  workload         = "platform"
  region_abbv      = "eus"
  address_space    = ["10.200.0.0/16"]
  enable_key_vault = false
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_key_vault"></a> [key\_vault](#module\_key\_vault) | ../key_vault | n/a |
| <a name="module_networking"></a> [networking](#module\_networking) | ../networking | n/a |
| <a name="module_resource_group"></a> [resource\_group](#module\_resource\_group) | ../resource_group | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_address_space"></a> [address\_space](#input\_address\_space) | VNet address space CIDR blocks | `list(string)` | n/a | yes |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (dev, staging, prod, ops) | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region | `string` | n/a | yes |
| <a name="input_name"></a> [name](#input\_name) | Base name used to derive resource names (resource group, VNet, key vault) | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviated region code for resource naming | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | n/a | yes |
| <a name="input_aks_cluster_name"></a> [aks\_cluster\_name](#input\_aks\_cluster\_name) | AKS cluster name (required if enable\_aks\_networking is true) | `string` | `null` | no |
| <a name="input_aks_subnet_name"></a> [aks\_subnet\_name](#input\_aks\_subnet\_name) | Subnet name for AKS nodes | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_enable_aks_networking"></a> [enable\_aks\_networking](#input\_enable\_aks\_networking) | Whether to configure AKS-specific networking (NSG rules, private DNS) | `bool` | `false` | no |
| <a name="input_enable_key_vault"></a> [enable\_key\_vault](#input\_enable\_key\_vault) | Whether to create a Key Vault as part of the base stack | `bool` | `true` | no |
| <a name="input_key_vault_sku"></a> [key\_vault\_sku](#input\_key\_vault\_sku) | Key Vault SKU (standard or premium) | `string` | `"standard"` | no |
| <a name="input_subnets"></a> [subnets](#input\_subnets) | Subnet definitions (same schema as the networking module) | <pre>map(object({<br/>    address_prefixes  = list(string)<br/>    service_endpoints = optional(list(string), [])<br/>    delegation        = optional(map(list(map(string))), {})<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_key_vault_id"></a> [key\_vault\_id](#output\_key\_vault\_id) | Key Vault ID (null if key vault disabled) |
| <a name="output_key_vault_name"></a> [key\_vault\_name](#output\_key\_vault\_name) | Key Vault name (null if key vault disabled) |
| <a name="output_key_vault_uri"></a> [key\_vault\_uri](#output\_key\_vault\_uri) | Key Vault URI (null if key vault disabled) |
| <a name="output_kubernetes_subnet_id"></a> [kubernetes\_subnet\_id](#output\_kubernetes\_subnet\_id) | Cloud-agnostic Kubernetes node subnet ID |
| <a name="output_location"></a> [location](#output\_location) | Azure region of the stack |
| <a name="output_network_id"></a> [network\_id](#output\_network\_id) | Cloud-agnostic network identifier |
| <a name="output_network_name"></a> [network\_name](#output\_network\_name) | Cloud-agnostic network name |
| <a name="output_resource_group_id"></a> [resource\_group\_id](#output\_resource\_group\_id) | ID of the created resource group |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | Name of the created resource group |
| <a name="output_subnet_ids"></a> [subnet\_ids](#output\_subnet\_ids) | Map of subnet names to IDs |
| <a name="output_vnet_id"></a> [vnet\_id](#output\_vnet\_id) | Virtual network ID |
| <a name="output_vnet_name"></a> [vnet\_name](#output\_vnet\_name) | Virtual network name |
<!-- END_TF_DOCS -->

## Notes

- The VNet name is derived from the `name` input as `{name}-vnet`. The Key Vault name is auto-generated by the key_vault module's naming logic.
- Key Vault creation is controlled by `enable_key_vault` (defaults to true). When disabled, `key_vault_id`, `key_vault_name`, and `key_vault_uri` outputs are null.
- AKS networking features (Cilium NSG rules, private DNS) are only configured when `enable_aks_networking = true` and `aks_subnet_name` points to a valid key in the `subnets` map.
- The module's resource group `name` and `location` outputs propagate to all child modules, ensuring consistent placement.
