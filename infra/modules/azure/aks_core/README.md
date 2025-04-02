# Azure Kubernetes Service (AKS) Core Module

## Overview

This module creates the essential components of an Azure Kubernetes Service (AKS) cluster, focusing on the core cluster functionality without additional features. It provides a production-ready foundation for Kubernetes workloads with flexible configuration options for identity, networking, and monitoring.

## Features

- Creates a production-ready AKS cluster with standardized naming conventions
- Supports both System-Assigned and User-Assigned managed identities
- Enables Workload Identity and OIDC issuer for modern authentication patterns
- Configurable default node pool with optional auto-scaling
- Integrates with Azure Monitor, Log Analytics, and Prometheus for comprehensive monitoring
- Supports private cluster deployment with custom networking
- Azure AD integration for role-based access control (RBAC)
- Azure Policy and cost analysis enabled by default

## Usage

```hcl
module "aks_core" {
  source = "../../modules/azure/aks_core"

  # Naming
  prefix      = "vip"
  environment = "dev"
  region_abbv = "eus"
  
  # Resource details
  resource_group_name = "rg-aks-dev-001"
  location            = "eastus"
  dns_prefix          = "aks-dev"
  
  # Identity (using System Assigned for simplicity)
  identity_type = "SystemAssigned"
  
  # Default node pool configuration
  default_nodepool_name    = "system"
  default_nodepool_vm_size = "Standard_D4s_v3"
  default_nodepool_count   = 3
  default_nodepool_enable_auto_scaling = true
  default_nodepool_min_count = 3
  default_nodepool_max_count = 5
  
  # Security and authentication
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  local_account_disabled    = true
  
  # Networking
  subnet_id                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-network/providers/Microsoft.Network/virtualNetworks/vnet-aks/subnets/aks-nodes"
  network_plugin           = "azure"
  network_policy           = "azure"
  
  # Monitoring
  log_analytics_workspace_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourcegroups/rg-monitoring/providers/microsoft.operationalinsights/workspaces/log-analytics-workspace"
  enable_prometheus_integration = true
  
  # Tags
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
    Component   = "Kubernetes"
  }
}
```

## Examples

### Basic Cluster with System-Assigned Identity

```hcl
module "aks_core" {
  source = "../../modules/azure/aks_core"

  prefix                    = "vip"
  environment               = "dev"
  region_abbv               = "eus"
  resource_group_name       = "rg-aks-dev-001"
  location                  = "eastus"
  identity_type             = "SystemAssigned"
  default_nodepool_name     = "system"
  default_nodepool_vm_size  = "Standard_D2s_v4"
  default_nodepool_count    = 1
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
}
```

### Production Cluster with Advanced Networking and Monitoring

```hcl
module "aks_core" {
  source = "../../modules/azure/aks_core"

  prefix                    = "vip"
  environment               = "prod"
  region_abbv               = "weu"
  resource_group_name       = "rg-aks-prod-001"
  location                  = "westeurope"
  
  # Production-grade SKU
  sku_tier                  = "Standard"
  
  # User-assigned identity for better RBAC control
  identity_type             = "UserAssigned"
  user_assigned_identity_id = module.aks_identity.id
  
  # Advanced default node pool configuration
  default_nodepool_name     = "system"
  default_nodepool_vm_size  = "Standard_D4s_v3"
  default_nodepool_count    = 3
  default_nodepool_enable_auto_scaling = true
  default_nodepool_min_count = 3
  default_nodepool_max_count = 5
  default_nodepool_max_pods = 30
  default_nodepool_os_disk_size_gb = 128
  default_nodepool_only_critical_addons_enabled = true
  
  # Private cluster configuration
  private_cluster_enabled   = true
  private_dns_zone_id       = module.private_dns.id
  
  # Advanced networking
  subnet_id                 = module.networking.subnet_id
  network_plugin            = "azure"
  network_policy            = "azure"
  service_cidr              = "172.16.0.0/16"
  dns_service_ip            = "172.16.0.10"
  
  # Security and authentication
  workload_identity_enabled = true
  oidc_issuer_enabled       = true
  local_account_disabled    = true
  
  # Azure AD integration
  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    azure_rbac_enabled     = true
  }
  
  # Comprehensive monitoring
  log_analytics_workspace_id = module.log_analytics.id
  enable_prometheus_integration = true
  prometheus_dcr_id = module.prometheus_dcr.id
  monitor_workspace_id = module.monitor_workspace.id
  
  # Automated upgrades
  automatic_channel_upgrade = "stable"
  
  # Tags
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
| azurerm | 4.25.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | 4.25.0 |

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| resource_group_name | The resource group name where the AKS cluster will be created | `string` |
| location | The Azure location where the AKS cluster will be deployed | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | Prefix for resource names | `string` | `"centric"` | no |
| environment | Environment name for resource tagging (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| region_abbv | Abbreviation for region (used in resource naming) | `string` | `"weu"` | no |
| name | Name of the AKS cluster resource (auto-generated if not provided) | `string` | `null` | no |
| dns_prefix | DNS prefix for the AKS cluster (auto-generated if not provided) | `string` | `null` | no |
| kubernetes_version | The Kubernetes version for the AKS cluster | `string` | `null` | no |
| automatic_channel_upgrade | The upgrade channel for the Kubernetes Cluster (patch, rapid, node-image, stable, none) | `string` | `"stable"` | no |
| local_account_disabled | If true, disable local accounts in Kubernetes | `bool` | `true` | no |
| sku_tier | The SKU tier for the AKS cluster (Free or Standard) | `string` | `"Free"` | no |
| private_cluster_enabled | Whether the AKS cluster is a private cluster | `bool` | `false` | no |
| private_dns_zone_id | The ID of the Private DNS Zone for private cluster | `string` | `null` | no |
| workload_identity_enabled | Enable or disable Workload Identity for the cluster | `bool` | `true` | no |
| oidc_issuer_enabled | Enable or disable the OIDC issuer URL | `bool` | `true` | no |
| identity_type | The type of identity to use (SystemAssigned or UserAssigned) | `string` | `"UserAssigned"` | no |
| user_assigned_identity_id | The ID of the User Assigned Identity (required when identity_type is UserAssigned) | `string` | `null` | no |
| default_nodepool_name | The name of the default node pool | `string` | `"system"` | no |
| default_nodepool_vm_size | The VM size for the default node pool | `string` | `"Standard_D2s_v4"` | no |
| default_nodepool_count | The initial node count for the default node pool | `number` | `1` | no |
| default_nodepool_enable_auto_scaling | Enable auto-scaling for the default node pool | `bool` | `false` | no |
| default_nodepool_min_count | Minimum node count for auto-scaling | `number` | `null` | no |
| default_nodepool_max_count | Maximum node count for auto-scaling | `number` | `null` | no |
| default_nodepool_max_pods | Maximum pods per node | `number` | `30` | no |
| default_nodepool_os_disk_size_gb | OS disk size for nodes (GB) | `number` | `128` | no |
| network_plugin | Network plugin for AKS (azure, kubenet, or none) | `string` | `"azure"` | no |
| network_policy | Network policy solution (azure, calico, or null) | `string` | `null` | no |
| subnet_id | The ID of the subnet where AKS nodes will be deployed | `string` | `null` | no |
| service_cidr | The CIDR range for Kubernetes services | `string` | `"10.0.0.0/16"` | no |
| dns_service_ip | The IP address for the Kubernetes DNS service | `string` | `"10.0.0.10"` | no |
| pod_cidr | The CIDR range for Kubernetes pods | `string` | `null` | no |
| outbound_type | The outbound (egress) routing method (loadBalancer, userDefinedRouting, managedNATGateway, userAssignedNATGateway) | `string` | `"loadBalancer"` | no |
| log_analytics_workspace_id | The ID of the Log Analytics workspace for monitoring | `string` | `null` | no |
| enable_prometheus_integration | Enable Prometheus metrics collection and integration | `bool` | `false` | no |
| prometheus_dcr_id | The ID of the Data Collection Rule for Prometheus | `string` | `null` | no |
| monitor_workspace_id | The ID of the Azure Monitor workspace for Prometheus | `string` | `null` | no |
| azure_active_directory_role_based_access_control | Azure AD RBAC configuration | `object` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| role_assignments | List of role assignments to create for the AKS cluster | `list(object)` | `[]` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the AKS cluster |
| name | The name of the AKS cluster |
| resource_group_name | The resource group name |
| location | The cluster location |
| kubernetes_version | The Kubernetes version |
| kube_config_raw | Raw Kubernetes config for authentication |
| kube_admin_config_raw | Raw Kubernetes admin config for authentication |
| host | The Kubernetes host |
| client_certificate | Client certificate for authentication |
| client_key | Client key for authentication |
| cluster_ca_certificate | CA certificate for authentication |
| default_node_pool_name | The name of the default node pool |
| node_resource_group | Node resource group name |
| node_resource_group_id | Node resource group ID |
| oidc_issuer_url | OIDC issuer URL |
| kubelet_identity | Kubelet managed identity |
| identity | Cluster identity |
| fqdn | Cluster FQDN |

## Validation Rules

The module includes comprehensive validation for input variables, including:
- Resource naming follows Azure constraints (length, character limitations)
- Environment must be one of the allowed values (dev, test, staging, prod, ops)
- Location must be a valid Azure region
- Network and CIDR configurations are validated for correct format
- Node pool parameters are validated for acceptable ranges

## Dependencies

This module can depend on:
- [naming](../naming) - For standardized resource naming
- [resource_group](../resource_group) - For resource group creation
- [networking](../networking) - For VNet and subnet configuration
- [identities](../identities) - For user-assigned managed identity
- [log_analytics](../log_analytics) - For logging and monitoring
- [monitor_workspace](../monitor_workspace) - For Prometheus integration
- [prometheus_dcr](../prometheus_dcr) - For Prometheus data collection rules

## Module Resources

This module creates the following resources:
- Azure Kubernetes Service (AKS) cluster
- Azure Monitor Data Collection Rule Association (when Prometheus is enabled)
- Azure Role Assignments (for monitoring metrics and custom RBAC)

## Notes

- This module creates the core AKS cluster without additional node pools. Use the [aks_node_pools](../aks_node_pools) module for additional node pools.
- The `network_plugin` can be set to "none" when planning to use Cilium CNI.
- For production clusters, it's recommended to set `sku_tier` to "Standard" for enhanced SLAs.
- Enable `workload_identity_enabled` and `oidc_issuer_enabled` for modern pod authentication methods.
- Consider using `automatic_channel_upgrade` for maintaining cluster health and security.

## License

This module is licensed under the MIT License. 