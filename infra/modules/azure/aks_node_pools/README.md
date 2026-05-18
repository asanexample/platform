# AKS Node Pools Module

Creates additional user node pools for an existing AKS cluster.

## Usage

```hcl
module "aks_node_pools" {
  source = "../aks_node_pools"

  create         = true
  aks_cluster_id = module.aks_core.id
  workload       = "platform"
  environment    = "dev"
  region_abbv    = "eus"

  app_node_pool_enabled            = true
  app_node_pool_vm_size            = "Standard_D4s_v4"
  app_node_pool_node_count         = 2
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count          = 1
  app_node_pool_max_count          = 5

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "aks_node_pools" {
  source = "../aks_node_pools"

  create         = false
  aks_cluster_id = "placeholder"
  region_abbv    = "eus"
}
```

### Node pool with taints for dedicated workloads

```hcl
module "aks_node_pools" {
  source = "../aks_node_pools"

  create         = true
  aks_cluster_id = module.aks_core.id
  region_abbv    = "eus"

  app_node_pool_name     = "gpu"
  app_node_pool_vm_size  = "Standard_NC6s_v3"
  app_node_pool_max_pods = 30

  app_node_pool_node_labels = {
    "accelerator" = "nvidia"
  }

  app_node_pool_node_taints = [
    "gpu=true:NoSchedule"
  ]
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_kubernetes_cluster_node_pool.app_node_pool](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster_node_pool) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| aks_cluster_id | The ID of the AKS cluster where node pools will be created | `string` | n/a | yes |
| region_abbv | The abbreviated Azure region name (e.g., wus, eus, neu). | `string` | n/a | yes |
| app_node_pool_availability_zones | Availability zones for the application node pool | `list(string)` | <pre>[<br/>  "1",<br/>  "2",<br/>  "3"<br/>]</pre> | no |
| app_node_pool_enable_auto_scaling | Enable auto-scaling for the application node pool | `bool` | `true` | no |
| app_node_pool_enabled | Enable application node pool | `bool` | `true` | no |
| app_node_pool_max_count | Maximum node count for auto-scaling | `number` | `5` | no |
| app_node_pool_max_pods | The maximum number of pods per node for the app node pool | `number` | `110` | no |
| app_node_pool_min_count | Minimum node count for auto-scaling | `number` | `1` | no |
| app_node_pool_mode | Mode for the application node pool (System or User) | `string` | `"User"` | no |
| app_node_pool_name | Name of the application node pool | `string` | `"apps"` | no |
| app_node_pool_node_count | Initial number of nodes in the application node pool | `number` | `2` | no |
| app_node_pool_node_labels | Labels to apply to nodes in the application node pool | `map(string)` | <pre>{<br/>  "app": "true",<br/>  "nodepool": "apps"<br/>}</pre> | no |
| app_node_pool_node_taints | A list of Kubernetes taints which should be applied to nodes in the application node pool | `list(string)` | `[]` | no |
| app_node_pool_os_disk_size_gb | OS disk size for nodes in the application node pool | `number` | `128` | no |
| app_node_pool_os_disk_type | OS disk type for nodes in the application node pool | `string` | `"Managed"` | no |
| app_node_pool_vm_size | VM size for the application node pool | `string` | `"Standard_D4s_v4"` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| environment | Environment name for resource tagging (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| workload | Workload name for resource names | `string` | `"platform"` | no |
| tags | Tags to apply to the node pools | `map(string)` | `{}` | no |
| temporary_name_for_rotation | Specifies the name of the temporary node pool used to cycle the node pool for updates | `string` | `null` | no |
| use_availability_zones | Controls whether to use availability zones for node pools. Set to false for regions that don't support zones for VMSS. | `bool` | `null` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| app_node_pool_auto_scaling_enabled | Whether auto-scaling is enabled for the application node pool |
| app_node_pool_id | The ID of the application node pool |
| app_node_pool_max_count | The maximum number of nodes in the application node pool |
| app_node_pool_min_count | The minimum number of nodes in the application node pool |
| app_node_pool_mode | The mode of the application node pool |
| app_node_pool_name | The name of the application node pool |
| app_node_pool_node_count | The number of nodes in the application node pool |
| app_node_pool_node_labels | The node labels of the application node pool |
| app_node_pool_os_disk_size_gb | The OS disk size of the application node pool |
| app_node_pool_vm_size | The VM size of the application node pool |
| create | Whether resources were created |
<!-- END_TF_DOCS -->

## Dependencies

- [aks_core](../aks_core) -- the AKS cluster where node pools are added
