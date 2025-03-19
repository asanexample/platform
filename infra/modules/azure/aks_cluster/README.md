# Azure Kubernetes Service (AKS) Cluster Module

This module creates an Azure Kubernetes Service (AKS) cluster with comprehensive security, monitoring, and identity integrations. The module follows Azure best practices for production-grade deployments.

## Features

- User-assigned managed identity for the AKS cluster
- Role-based access control (RBAC) integration with Azure AD
- Private cluster deployment option with custom DNS settings
- Configurable node pools with auto-scaling capabilities
- Integration with Azure Monitor and Log Analytics
- Support for monitoring with Azure Container Insights and Prometheus metrics
- Comprehensive diagnostic settings for better observability
- Robust security settings including host encryption and Azure Policy
- Workload identity integration for secure access to Azure resources

## Usage

```hcl
module "aks_cluster" {
  source = "../modules/azure/aks_cluster"

  # Naming
  name_prefix        = "prod"
  name_suffix        = "001"
  resource_group_name = "rg-aks-prod-001"
  location           = "westeurope"
  
  # Basic cluster settings
  kubernetes_version = "1.27"
  dns_prefix         = "aks-prod"
  
  # Identity and access
  identity_ids       = [azurerm_user_assigned_identity.aks_identity.id]
  
  # Networking
  network_plugin     = "azure"
  network_policy     = "azure"
  
  # Node pools
  default_node_pool = {
    name                = "system"
    node_count          = 3
    vm_size             = "Standard_D4s_v3"
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    max_pods            = 50
    enable_auto_scaling = true
    min_count           = 2
    max_count           = 5
  }
  
  # Monitoring
  log_analytics_workspace_id = azurerm_log_analytics_workspace.aks.id
  
  # Tags
  tags = {
    Environment = "Production"
    Application = "Core Infrastructure"
    ManagedBy   = "Terraform"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | 4.23.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name_prefix | Prefix to use for resource names | `string` | n/a | yes |
| name_suffix | Suffix to use for resource names | `string` | n/a | yes |
| custom_name | Custom name for the AKS cluster | `string` | `null` | no |
| resource_group_name | Resource group name where the AKS cluster will be deployed | `string` | n/a | yes |
| location | Azure region where the AKS cluster will be deployed | `string` | n/a | yes |
| kubernetes_version | Version of Kubernetes to use for the AKS cluster | `string` | `null` | no |
| dns_prefix | DNS prefix specified when creating the managed cluster | `string` | n/a | yes |
| sku_tier | The SKU Tier for the Kubernetes cluster. Possible values are Free, Standard, Premium | `string` | `"Free"` | no |
| default_node_pool | Configuration for the default node pool | `object` | See default values | yes |
| app_node_pool | Configuration for the additional application node pool | `object` | `null` | no |
| identity_ids | List of User Assigned Managed Identity IDs | `list(string)` | `[]` | no |
| private_cluster_enabled | Whether to enable private cluster for AKS | `bool` | `false` | no |
| private_dns_zone_id | The ID of the Private DNS Zone for the private cluster | `string` | `"System"` | no |
| private_cluster_public_fqdn_enabled | Whether to create additional public FQDN for private cluster | `bool` | `false` | no |
| authorized_ip_ranges | List of authorized IP ranges to access the Kubernetes API server | `list(string)` | `[]` | no |
| azure_rbac_enabled | Whether to enable Azure RBAC for access to the cluster | `bool` | `true` | no |
| admin_group_object_ids | List of Azure AD group object IDs with admin access | `list(string)` | `[]` | no |
| network_plugin | Network plugin to use for networking | `string` | `"azure"` | no |
| network_plugin_mode | Network plugin mode to use | `string` | `null` | no |
| network_policy | Network policy to use for networking | `string` | `"azure"` | no |
| network_data_plane | Network data plane to use | `string` | `null` | no |
| log_analytics_workspace_id | Log Analytics Workspace ID for monitoring | `string` | `null` | no |
| azure_monitor_workspace_id | Azure Monitor Workspace ID for container insights | `string` | `null` | no |
| diagnostic_settings | Diagnostic settings for the AKS cluster | `object` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the AKS cluster |
| name | The name of the AKS cluster |
| resource_group_name | Resource group name of the AKS cluster |
| location | The location of the AKS cluster |
| kubernetes_version | The version of Kubernetes used on the AKS cluster |
| kube_config_raw | Raw Kubernetes config to authenticate with the cluster |
| default_node_pool_id | The ID of the default node pool |
| app_node_pool_id | The ID of the application node pool, if enabled |
| kubelet_identity | The Managed Identity used by the AKS kubelet |
| identity | The identity used by the AKS cluster |
| node_resource_group | The auto-generated resource group name for the AKS cluster nodes |
| network_profile | Network profile configuration of the AKS cluster |
| private_fqdn | The private FQDN of the AKS cluster |
| fqdn | The FQDN of the AKS cluster |

## Notes

- The module supports both public and private cluster configurations
- For private clusters, it's recommended to configure a proper DNS zone and network integration
- Role assignments are created to grant the AKS managed identity necessary permissions
- Log Analytics integration is optional but recommended for monitoring 