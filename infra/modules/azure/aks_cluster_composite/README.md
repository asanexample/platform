# AKS Cluster Composite Module

This module creates a complete AKS cluster solution by integrating multiple specialized modules, following the principles of separation of concerns and modularity.

## Architecture

The composite module orchestrates the following specialized modules to create a complete AKS solution:

1. **AKS Identity Module** - Creates and manages the identities required for the AKS cluster and workloads
2. **AKS Networking Module** - Configures networking resources and settings for the cluster
3. **AKS Core Module** - Creates the core AKS cluster resource with basic configuration
4. **AKS Monitoring Module** - Configures logging, monitoring, and diagnostics
5. **AKS Node Pools Module** - Configures additional node pools for workloads

This modular approach provides several benefits:
- Each component can be tested independently
- Easier to maintain and update individual parts
- Clearer separation of responsibilities
- More focused modules with specific purposes
- Improved testability and reusability

## Features

- **Comprehensive Identity Management**
  - User-assigned managed identities for the AKS cluster
  - Workload identity federation for pods
  - Federated credentials for external services
  
- **Advanced Networking Options**
  - Support for Azure CNI and kubenet networking
  - Private cluster configuration
  - Network policy enforcement
  - Flexible CIDR configuration

- **Custom Node Pool Management**
  - System and application node pools
  - Auto-scaling configuration
  - Node taints and labels
  
- **Integrated Monitoring**
  - Log Analytics integration
  - Diagnostic settings for key resources
  - Azure Monitor for containers

- **Security Best Practices**
  - Azure RBAC integration
  - Network security controls
  - Private cluster options

## Usage

### Basic Usage

```hcl
module "aks_cluster" {
  source = "../modules/azure/aks_cluster_composite"
  
  # Naming
  prefix      = "vip"
  customer    = "example"
  stage       = "dev"
  region_abbv = "eus"
  
  # Resource group
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = azurerm_resource_group.aks_rg.location
  
  # Network configuration
  subnet_id           = azurerm_subnet.aks_subnet.id
  network_plugin      = "azure"
  network_plugin_mode = "overlay"
  pod_cidr            = "10.244.0.0/16"
  service_cidr        = "10.0.0.0/16"
  dns_service_ip      = "10.0.0.10"
  
  # Monitoring
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  
  # Default tags
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
    Project     = "AKS Platform"
  }
}
```

### Advanced Configuration

```hcl
module "production_aks" {
  source = "../modules/azure/aks_cluster_composite"
  
  # Naming
  prefix      = "vip"
  customer    = "example"
  stage       = "prod"
  region_abbv = "eus"
  
  # Resource group
  resource_group_name = azurerm_resource_group.aks_rg.name
  location            = azurerm_resource_group.aks_rg.location
  
  # Cluster basics
  kubernetes_version  = "1.28.0"
  sku_tier            = "Standard"
  
  # Network configuration
  subnet_id                  = azurerm_subnet.aks_subnet.id
  network_plugin             = "azure"
  network_plugin_mode        = "overlay"
  network_policy             = "azure"
  pod_cidr                   = "10.244.0.0/16"
  service_cidr               = "10.0.0.0/16"
  dns_service_ip             = "10.0.0.10"
  private_cluster_enabled    = true
  private_dns_zone_id        = azurerm_private_dns_zone.aks.id
  authorized_ip_ranges       = ["203.0.113.0/24", "198.51.100.0/24"]
  
  # Default node pool
  default_nodepool_name      = "system"
  default_nodepool_vm_size   = "Standard_D4s_v4"
  default_nodepool_count     = 3
  
  # App node pool
  app_node_pool_enabled        = true
  app_node_pool_name           = "apps"
  app_node_pool_vm_size        = "Standard_D8s_v4"
  app_node_pool_node_count     = 5
  app_node_pool_max_pods       = 50
  app_node_pool_os_disk_size_gb = 256
  app_node_pool_enable_auto_scaling = true
  app_node_pool_min_count      = 3
  app_node_pool_max_count      = 10
  app_node_pool_node_labels    = {
    "workload-type" = "application"
    "environment"   = "production"
  }
  
  # Monitoring
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  
  # Default tags
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Project     = "AKS Platform"
    CostCenter  = "IT-Cloud-Platform"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | Prefix used in resource naming | `string` | `"vip"` | no |
| customer | Customer name for resource naming | `string` | `"shared"` | no |
| stage | Environment stage (dev, test, staging, prod) | `string` | `"dev"` | yes |
| region_abbv | Abbreviated Azure region code | `string` | `"weu"` | no |
| name | AKS cluster name (overrides auto-generated name) | `string` | `""` | no |
| resource_group_name | Resource group name | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| kubernetes_version | Kubernetes version | `string` | `null` | no |
| sku_tier | AKS SKU tier (Free or Standard) | `string` | `"Free"` | no |
| network_plugin | Network plugin (azure, kubenet) | `string` | `"azure"` | no |
| subnet_id | Subnet ID for AKS deployment | `string` | n/a | yes |
| log_analytics_workspace_id | Log Analytics workspace ID | `string` | n/a | yes |
| private_cluster_enabled | Enable private cluster | `bool` | `false` | no |

## Outputs

| Name | Description |
|------|-------------|
| cluster_id | The AKS cluster ID |
| cluster_name | The AKS cluster name |
| kube_config | Kubernetes config to connect to the cluster |
| kube_admin_config | Kubernetes admin config to connect to the cluster |
| node_resource_group | The auto-generated resource group name for cluster resources |
| kubelet_identity | The kubelet managed identity |
| oidc_issuer_url | The OIDC issuer URL for the cluster |

## Additional Resources

For more information on each specialized module, refer to their individual documentation:

- [AKS Core Module](../aks_core/README.md)
- [AKS Identity Module](../aks_identity/README.md)
- [AKS Networking Module](../aks_networking/README.md)
- [AKS Monitoring Module](../aks_monitoring/README.md)
- [AKS Node Pools Module](../aks_node_pools/README.md) 