# AKS Core Module

Creates an AKS cluster with a system node pool and core cluster configuration.

## Usage

```hcl
module "aks_core" {
  source = "../aks_core"

  create              = true
  resource_group_name = module.resource_group.name
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"

  identity_type             = "UserAssigned"
  user_assigned_identity_id = module.aks_identity.aks_identity_id

  subnet_id      = module.networking.kubernetes_subnet_id
  network_plugin = "none"

  default_nodepool_vm_size             = "Standard_D4s_v3"
  default_nodepool_count               = 2
  default_nodepool_enable_auto_scaling = true
  default_nodepool_min_count           = 2
  default_nodepool_max_count           = 5

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "aks_core" {
  source = "../aks_core"

  create              = false
  resource_group_name = "placeholder"
  location            = "eastus"
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_kubernetes_cluster.aks_cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_monitor_data_collection_rule_association.prometheus](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [azurerm_role_assignment.prometheus_publisher](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | The Azure location where the AKS cluster will be deployed | `string` | n/a | yes |
| resource_group_name | The resource group name where the AKS cluster will be created | `string` | n/a | yes |
| authorized_ip_ranges | The IP ranges authorized for API server access | `list(string)` | `null` | no |
| automatic_channel_upgrade | The upgrade channel for this Kubernetes Cluster. Possible values are patch, rapid, node-image and stable. | `string` | `"stable"` | no |
| azure_active_directory_role_based_access_control | Azure Active Directory RBAC configuration for AKS | <pre>object({<br/>    admin_group_object_ids = list(string)<br/>    azure_rbac_enabled     = bool<br/>  })</pre> | `null` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| create_kubeconfig | Whether to create a local kubeconfig file | `bool` | `false` | no |
| default_nodepool_count | Initial node count for the default node pool | `number` | `1` | no |
| default_nodepool_enable_auto_scaling | Whether auto-scaling is enabled for the default node pool | `bool` | `true` | no |
| default_nodepool_max_count | Maximum node count for the default node pool | `number` | `3` | no |
| default_nodepool_max_pods | The maximum number of pods per node for the default node pool | `number` | `30` | no |
| default_nodepool_min_count | Minimum node count for the default node pool | `number` | `1` | no |
| default_nodepool_name | Name of the default node pool | `string` | `"system"` | no |
| default_nodepool_node_labels | The node labels for the default node pool | `map(string)` | `{}` | no |
| default_nodepool_only_critical_addons_enabled | Whether to taint the default node pool with CriticalAddonsOnly=true:NoSchedule to ensure only critical addons are scheduled on it | `bool` | `false` | no |
| default_nodepool_os_disk_size_gb | OS disk size in GB for the default node pool | `number` | `128` | no |
| default_nodepool_vm_size | VM size for the default node pool | `string` | `"Standard_D2s_v3"` | no |
| diagnostic_settings | A list of diagnostic settings to create for the AKS cluster | <pre>list(object({<br/>    name                       = string<br/>    log_analytics_workspace_id = string<br/>    enabled_log_categories     = list(string)<br/>    metric_categories          = list(string)<br/>    log_retention_days         = optional(number)<br/>  }))</pre> | `[]` | no |
| dns_prefix | DNS prefix for the AKS cluster | `string` | `null` | no |
| dns_service_ip | The IP address for the DNS service | `string` | `"10.0.0.10"` | no |
| docker_bridge_cidr | The CIDR for the Docker bridge network | `string` | `"172.17.0.1/16"` | no |
| enable_azure_policy | Whether Azure Policy is enabled for the AKS cluster | `bool` | `true` | no |
| enable_host_encryption | Whether host encryption is enabled for the AKS cluster | `bool` | `false` | no |
| enable_prometheus_integration | Whether to enable the Azure Monitor managed service for Prometheus integration. | `bool` | `true` | no |
| environment | Environment name for resource tagging (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| identity_type | The type of identity to use for the cluster | `string` | `"UserAssigned"` | no |
| kubernetes_version | The Kubernetes version for the AKS cluster | `string` | `null` | no |
| local_account_disabled | If true, disable local accounts in Kubernetes | `bool` | `true` | no |
| log_analytics_workspace_id | The ID of the Log Analytics workspace for container insights | `string` | `null` | no |
| monitor_workspace_id | The ID of the Azure Monitor Workspace where Prometheus metrics are sent. Required if enable_prometheus_integration is true. | `string` | `null` | no |
| name | Name of the AKS cluster resource. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| network_plugin | The network plugin to use for the AKS cluster | `string` | `"azure"` | no |
| network_policy | The network policy to use for the AKS cluster | `string` | `null` | no |
| oidc_issuer_enabled | Enable or disable the OIDC issuer URL | `bool` | `true` | no |
| outbound_type | The outbound (egress) routing method for the AKS cluster | `string` | `"loadBalancer"` | no |
| pod_cidr | The CIDR for pod IPs when using kubenet | `string` | `null` | no |
| workload | Workload name for resource names | `string` | `"platform"` | no |
| private_cluster_enabled | Whether the AKS cluster is a private cluster | `bool` | `false` | no |
| private_dns_zone_id | The ID of the Private DNS Zone for private cluster | `string` | `null` | no |
| prometheus_dcr_id | The ID of the Azure Monitor data collection rule for Prometheus metrics. If null and enable_prometheus_integration is true, integration will not be configured. | `string` | `null` | no |
| region_abbv | Abbreviation for region (used in resource naming) | `string` | `"weu"` | no |
| role_assignments | A list of role assignments to create for the AKS cluster | <pre>list(object({<br/>    principal_id         = string<br/>    role_definition_name = string<br/>    description          = optional(string, null)<br/>  }))</pre> | `[]` | no |
| service_cidr | The CIDR for Kubernetes services | `string` | `"10.0.0.0/16"` | no |
| sku_tier | The SKU tier for the AKS cluster (Free or Standard) | `string` | `"Free"` | no |
| subnet_id | The ID of the subnet where the AKS cluster will be deployed | `string` | `null` | no |
| tags | A map of tags to apply to all resources | `map(string)` | `{}` | no |
| user_assigned_identity_id | The ID of the user-assigned identity for the AKS cluster | `string` | `null` | no |
| workload_identity_enabled | Enable or disable Workload Identity for the cluster | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| client_certificate | The client certificate for authentication |
| client_key | The client key for authentication |
| cluster_ca_certificate | The cluster CA certificate for communication with the cluster |
| create | Whether resources were created |
| default_node_pool_name | The name of the default node pool |
| fqdn | The FQDN of the AKS cluster |
| host | The Kubernetes cluster server host |
| id | The ID of the AKS cluster |
| identity | The identity of the AKS cluster |
| kube_admin_config_raw | The raw Kubernetes admin config to be used with kubectl and other tools |
| kube_config_raw | The raw Kubernetes config to be used with kubectl and other tools |
| kubelet_identity | The kubelet managed identity assigned to the AKS cluster |
| kubernetes_version | The version of Kubernetes running on the AKS cluster |
| location | The location/region of the AKS cluster |
| name | The name of the AKS cluster |
| node_resource_group | The name of the resource group containing the AKS cluster's node resources |
| node_resource_group_id | The ID of the resource group containing the AKS cluster's node resources |
| oidc_issuer_url | The OIDC issuer URL of the AKS cluster |
| resource_group_name | The name of the resource group that contains the AKS cluster |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) -- standardized resource names
- [resource_group](../resource_group) -- resource group for the cluster
- [networking](../networking) -- VNet/subnet for node placement
- [aks_identity](../aks_identity) -- user-assigned managed identity for the cluster control plane

## Notes

- Uses BYOCNI mode (`network_plugin = "none"`) when deploying with Cilium; set `network_plugin = "azure"` for Azure CNI.
- OIDC issuer is enabled by default to support workload identity federation.
- Local accounts are disabled by default; access requires Azure AD integration.
- This module creates only the core cluster and system node pool. Use [aks_node_pools](../aks_node_pools) for additional pools.
