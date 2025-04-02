# Azure Kubernetes Service (AKS) Node Pools Module

## Overview

This module creates additional node pools for an existing Azure Kubernetes Service (AKS) cluster. It allows creating application-specific node pools with custom configurations, enabling workload isolation and optimization strategies.

## Features

- Creates application-specific node pools for an existing AKS cluster
- Supports multiple availability zones for high availability
- Configurable auto-scaling for dynamic workload demands
- Custom node labels and taints for workload targeting and isolation
- Optimizable VM sizes, OS disk configurations, and pod limits
- Compatible with the AKS Core module for complete cluster management

## Usage

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"

  # Naming
  prefix      = "vip"
  environment = "dev"
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
    Component   = "Kubernetes"
  }
}
```

## Examples

### Basic Application Node Pool

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"

  prefix      = "vip"
  environment = "dev"
  region_abbv = "eus"
  aks_cluster_id = module.aks_core.id
  
  app_node_pool_enabled = true
  app_node_pool_vm_size = "Standard_D4s_v4"
  app_node_pool_node_count = 2
}
```

### High-Performance Workload Node Pool

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"

  prefix      = "vip"
  environment = "prod"
  region_abbv = "weu"
  aks_cluster_id = module.aks_core.id
  
  app_node_pool_enabled = true
  app_node_pool_name = "gpu"
  app_node_pool_vm_size = "Standard_NC6s_v3"
  app_node_pool_node_count = 2
  app_node_pool_os_disk_size_gb = 256
  app_node_pool_max_pods = 20
  
  app_node_pool_node_labels = {
    "nodepool" = "gpu"
    "accelerator" = "nvidia"
  }
  
  app_node_pool_node_taints = [
    "gpu=true:NoSchedule"
  ]
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Kubernetes"
    Workload    = "GPU"
  }
}
```

### Auto-Scaling Production Node Pool

```hcl
module "aks_node_pools" {
  source = "../../modules/azure/aks_node_pools"

  prefix      = "vip"
  environment = "prod"
  region_abbv = "eus"
  aks_cluster_id = module.aks_core.id
  
  app_node_pool_enabled = true
  app_node_pool_vm_size = "Standard_D8s_v4"
  app_node_pool_node_count = 3
  app_node_pool_availability_zones = ["1", "2", "3"]
  app_node_pool_os_disk_size_gb = 256
  app_node_pool_max_pods = 50
  
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count = 3
  app_node_pool_max_count = 10
  
  app_node_pool_node_labels = {
    "nodepool" = "apps"
    "environment" = "production"
    "criticality" = "high"
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Kubernetes"
    CostCenter  = "Platform"
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
| aks_cluster_id | ID of the existing AKS cluster | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | Prefix for resource names | `string` | `"centric"` | no |
| environment | Environment name for resource tagging (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| region_abbv | Abbreviation for region (used in resource naming) | `string` | `"weu"` | no |
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
| app_node_pool_mode | Node pool mode (User or System) | `string` | `"User"` | no |
| app_node_pool_node_labels | Node labels | `map(string)` | `{"nodepool" = "apps", "app" = "true"}` | no |
| app_node_pool_node_taints | Node taints | `list(string)` | `[]` | no |
| tags | Tags to apply to resources | `map(string)` | `{}` | no |

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

## Module Resources

This module creates the following resources:
- Kubernetes node pool for an existing AKS cluster

## Dependencies

This module depends on:
- [aks_core](../aks_core) - For the AKS cluster reference

## Notes

- This module is designed to be used with the AKS Core module as part of a modular AKS deployment
- For multiple node pools of different types, call this module multiple times with different configurations
- Consider using node labels and taints to control workload placement across node pools
- Ensure node VM sizes are appropriate for your workload requirements
- For production environments, using multiple availability zones is recommended for high availability
- Use auto-scaling for workloads with variable resource demands to optimize costs

## License

This module is licensed under the MIT License. 