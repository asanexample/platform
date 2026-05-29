# AKS Node Pools

Creates additional node pools for an existing AKS cluster, separate from the system (default) node pool defined in `aks_core`. This module provisions an application-tier node pool with configurable VM size, auto-scaling, availability zones, disk settings, labels, and taints. Node pool names are limited to 12 lowercase alphanumeric characters per AKS constraints.

## Usage

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"

  aks_cluster_id = "/subscriptions/.../managedClusters/aks-platform-dev-eus"
  workload       = "platform"
  environment    = "dev"
  region_abbv    = "eus"

  app_node_pool_vm_size            = "Standard_D4s_v4"
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count           = 1
  app_node_pool_max_count           = 5
  app_node_pool_max_pods            = 110
  app_node_pool_os_disk_size_gb     = 128

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"
  create = false
}
```

### Region Without Availability Zones

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"

  aks_cluster_id         = "/subscriptions/.../managedClusters/aks-platform-dev-wus"
  workload               = "platform"
  environment            = "dev"
  region_abbv            = "wus"
  use_availability_zones = false

  app_node_pool_vm_size = "Standard_D4s_v4"
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
| [azurerm_kubernetes_cluster_node_pool.app_node_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_aks_cluster_id"></a> [aks\_cluster\_id](#input\_aks\_cluster\_id) | The ID of the AKS cluster where node pools will be created | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | The abbreviated Azure region name (e.g., wus, eus, neu). | `string` | n/a | yes |
| <a name="input_app_node_pool_availability_zones"></a> [app\_node\_pool\_availability\_zones](#input\_app\_node\_pool\_availability\_zones) | Availability zones for the application node pool | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| <a name="input_app_node_pool_enable_auto_scaling"></a> [app\_node\_pool\_enable\_auto\_scaling](#input\_app\_node\_pool\_enable\_auto\_scaling) | Enable auto-scaling for the application node pool | `bool` | `true` | no |
| <a name="input_app_node_pool_enabled"></a> [app\_node\_pool\_enabled](#input\_app\_node\_pool\_enabled) | Enable application node pool | `bool` | `true` | no |
| <a name="input_app_node_pool_max_count"></a> [app\_node\_pool\_max\_count](#input\_app\_node\_pool\_max\_count) | Maximum node count for auto-scaling | `number` | `5` | no |
| <a name="input_app_node_pool_max_pods"></a> [app\_node\_pool\_max\_pods](#input\_app\_node\_pool\_max\_pods) | The maximum number of pods per node for the app node pool | `number` | `110` | no |
| <a name="input_app_node_pool_min_count"></a> [app\_node\_pool\_min\_count](#input\_app\_node\_pool\_min\_count) | Minimum node count for auto-scaling | `number` | `1` | no |
| <a name="input_app_node_pool_mode"></a> [app\_node\_pool\_mode](#input\_app\_node\_pool\_mode) | Mode for the application node pool (System or User) | `string` | `"User"` | no |
| <a name="input_app_node_pool_name"></a> [app\_node\_pool\_name](#input\_app\_node\_pool\_name) | Name of the application node pool | `string` | `"apps"` | no |
| <a name="input_app_node_pool_node_count"></a> [app\_node\_pool\_node\_count](#input\_app\_node\_pool\_node\_count) | Initial number of nodes in the application node pool | `number` | `2` | no |
| <a name="input_app_node_pool_node_labels"></a> [app\_node\_pool\_node\_labels](#input\_app\_node\_pool\_node\_labels) | Labels to apply to nodes in the application node pool | `map(string)` | <pre>{<br/>  "app": "true",<br/>  "nodepool": "apps"<br/>}</pre> | no |
| <a name="input_app_node_pool_node_taints"></a> [app\_node\_pool\_node\_taints](#input\_app\_node\_pool\_node\_taints) | A list of Kubernetes taints which should be applied to nodes in the application node pool | `list(string)` | `[]` | no |
| <a name="input_app_node_pool_os_disk_size_gb"></a> [app\_node\_pool\_os\_disk\_size\_gb](#input\_app\_node\_pool\_os\_disk\_size\_gb) | OS disk size for nodes in the application node pool | `number` | `128` | no |
| <a name="input_app_node_pool_os_disk_type"></a> [app\_node\_pool\_os\_disk\_type](#input\_app\_node\_pool\_os\_disk\_type) | OS disk type for nodes in the application node pool | `string` | `"Managed"` | no |
| <a name="input_app_node_pool_vm_size"></a> [app\_node\_pool\_vm\_size](#input\_app\_node\_pool\_vm\_size) | VM size for the application node pool | `string` | `"Standard_D4s_v4"` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name for resource tagging (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the node pools | `map(string)` | `{}` | no |
| <a name="input_temporary_name_for_rotation"></a> [temporary\_name\_for\_rotation](#input\_temporary\_name\_for\_rotation) | Specifies the name of the temporary node pool used to cycle the node pool for updates | `string` | `null` | no |
| <a name="input_use_availability_zones"></a> [use\_availability\_zones](#input\_use\_availability\_zones) | Controls whether to use availability zones for node pools. Set to false for regions that don't support zones for VMSS. | `bool` | `null` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_app_node_pool_auto_scaling_enabled"></a> [app\_node\_pool\_auto\_scaling\_enabled](#output\_app\_node\_pool\_auto\_scaling\_enabled) | Whether auto-scaling is enabled for the application node pool |
| <a name="output_app_node_pool_id"></a> [app\_node\_pool\_id](#output\_app\_node\_pool\_id) | The ID of the application node pool |
| <a name="output_app_node_pool_max_count"></a> [app\_node\_pool\_max\_count](#output\_app\_node\_pool\_max\_count) | The maximum number of nodes in the application node pool |
| <a name="output_app_node_pool_min_count"></a> [app\_node\_pool\_min\_count](#output\_app\_node\_pool\_min\_count) | The minimum number of nodes in the application node pool |
| <a name="output_app_node_pool_mode"></a> [app\_node\_pool\_mode](#output\_app\_node\_pool\_mode) | The mode of the application node pool |
| <a name="output_app_node_pool_name"></a> [app\_node\_pool\_name](#output\_app\_node\_pool\_name) | The name of the application node pool |
| <a name="output_app_node_pool_node_count"></a> [app\_node\_pool\_node\_count](#output\_app\_node\_pool\_node\_count) | The number of nodes in the application node pool |
| <a name="output_app_node_pool_node_labels"></a> [app\_node\_pool\_node\_labels](#output\_app\_node\_pool\_node\_labels) | The node labels of the application node pool |
| <a name="output_app_node_pool_os_disk_size_gb"></a> [app\_node\_pool\_os\_disk\_size\_gb](#output\_app\_node\_pool\_os\_disk\_size\_gb) | The OS disk size of the application node pool |
| <a name="output_app_node_pool_vm_size"></a> [app\_node\_pool\_vm\_size](#output\_app\_node\_pool\_vm\_size) | The VM size of the application node pool |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
<!-- END_TF_DOCS -->

## Notes

- With BYOCNI (Cilium), `max_pods` defaults to 110, which is higher than the Azure CNI default of 30, because pod IP allocation is not constrained by Azure subnet sizing.
- The `use_availability_zones` variable overrides zone placement for regions like `westus` that do not support VMSS availability zones.
- When `app_node_pool_enable_auto_scaling` is true, `node_count` changes are ignored in the lifecycle block to avoid conflicts with the autoscaler.
- Set `temporary_name_for_rotation` to enable in-place updates for properties that normally require node pool recreation.
