# AKS Node Pools Module

This module creates additional node pools for an existing Azure Kubernetes Service (AKS) cluster. It's designed to be used in conjunction with the AKS Core module, following the principle of separation of concerns.

## Features

- Creates application-specific node pools for an existing AKS cluster
- Uses standardized naming conventions via the naming module
- Configurable auto-scaling capabilities
- Support for node labels and taints
- Customizable VM sizes, OS disk configurations, and pod limits

## Usage

```hcl
module "aks_node_pools" {
  source = "../modules/azure/aks_node_pools"

  # Naming
  prefix      = "vip"
  stage       = "dev"
  region_abbv = "eus"
  
  # Reference to existing AKS cluster
  aks_cluster_id = module.aks_core.id
  
  # App node pool configuration
  app_node_pool_enabled    = true
  app_node_pool_vm_size    = "Standard_D4s_v4"
  app_node_pool_node_count = 3
  app_node_pool_os_disk_size_gb = 128
  app_node_pool_max_pods   = 30
  
  # Auto-scaling configuration
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count           = 1
  app_node_pool_max_count           = 5
  
  # Node labels for workload targeting
  app_node_pool_node_labels = {
    "nodepool" = "apps"
    "app"      = "true"
    "tier"     = "backend"
  }

  # Tags
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

## Dependencies

This module depends on:
- An existing AKS cluster (from the aks_core module)
- The Azure naming module for resource naming

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | 4.23.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | Prefix to use for resource names | `string` | `"vip"` | no |
| customer | Customer name for resource naming | `string` | `null` | no |
| stage | Environment stage (dev, preprod, prod, test, stg) | `string` | n/a | yes |
| region_abbv | Abbreviated Azure region name | `string` | n/a | yes |
| aks_cluster_id | ID of the existing AKS cluster | `string` | n/a | yes |
| app_node_pool_enabled | Enable application node pool | `bool` | `true` | no |
| app_node_pool_name | Application node pool name | `string` | `"apps"` | no |
| app_node_pool_vm_size | VM size for application nodes | `string` | `"Standard_D4s_v4"` | no |
| app_node_pool_node_count | Initial node count | `number` | `2` | no |
| app_node_pool_availability_zones | Availability zones to use | `list(string)` | `["1", "2", "3"]` | no |
| app_node_pool_max_pods | Maximum pods per node | `number` | `30` | no |
| app_node_pool_os_disk_size_gb | OS disk size in GB | `number` | `128` | no |
| app_node_pool_os_disk_type | OS disk type | `string` | `"Managed"` | no |
| app_node_pool_enable_auto_scaling | Enable auto-scaling | `bool` | `true` | no |
| app_node_pool_min_count | Minimum node count | `number` | `1` | no |
| app_node_pool_max_count | Maximum node count | `number` | `5` | no |
| app_node_pool_mode | Node pool mode | `string` | `"User"` | no |
| app_node_pool_node_labels | Node labels | `map(string)` | `{"nodepool" = "apps", "app" = "true"}` | no |
| app_node_pool_node_taints | Node taints | `list(string)` | `[]` | no |
| tags | Resource tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| app_node_pool_id | The ID of the application node pool |
| app_node_pool_name | The name of the application node pool |
| app_node_pool_node_count | The number of nodes in the pool |
| app_node_pool_vm_size | The VM size used |
| app_node_pool_os_disk_size_gb | The OS disk size |
| app_node_pool_auto_scaling_enabled | Whether auto-scaling is enabled |
| app_node_pool_min_count | The minimum node count |
| app_node_pool_max_count | The maximum node count |
| app_node_pool_mode | The mode of the node pool |
| app_node_pool_node_labels | The node labels |

## Notes

- This module is designed to be used with AKS Core as part of a modular AKS deployment
- For additional node pools, consider extending this module or creating a new one with similar patterns
- The module follows the principle of separation of concerns by focusing solely on node pools 