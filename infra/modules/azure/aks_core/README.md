# AKS Core

Creates the core Azure Kubernetes Service (AKS) cluster resource with its system (default) node pool. This module handles cluster-level configuration including Kubernetes version, network plugin, identity, API server access, Azure AD RBAC integration, and Prometheus monitoring. It supports BYOCNI mode (`network_plugin = "none"`) for Cilium deployments, private clusters with custom DNS zones, and workload identity with OIDC issuer. Azure Policy and cost analysis are always enabled. The system node pool is configured inline; additional node pools should be added via the `aks_node_pools` module.

## Usage

```hcl
module "aks" {
  source = "../../modules/azure/aks_core"

  name                = "aks-platform-dev-eus"
  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"

  kubernetes_version       = "1.30.7"
  network_plugin           = "none"
  sku_tier                 = "Standard"
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  subnet_id                = "/subscriptions/.../subnets/snet-kubernetes"
  user_assigned_identity_id = "/subscriptions/.../userAssignedIdentities/aksid-platform-dev-eus"

  service_cidr   = "10.0.0.0/16"
  dns_service_ip = "10.0.0.10"

  default_nodepool_vm_size  = "Standard_D2s_v3"
  default_nodepool_count    = 1
  default_nodepool_max_pods = 110

  azure_active_directory_role_based_access_control = {
    admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
    azure_rbac_enabled     = true
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "aks" {
  source = "../../modules/azure/aks_core"
  create = false
}
```

### Private Cluster with Cilium BYOCNI

```hcl
module "aks" {
  source = "../../modules/azure/aks_core"

  name                = "aks-platform-prod-eus"
  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"

  kubernetes_version        = "1.30.7"
  network_plugin            = "none"
  sku_tier                  = "Standard"
  private_cluster_enabled   = true
  private_dns_zone_id       = "/subscriptions/.../privateDnsZones/privatelink.eastus.azmk8s.io"
  local_account_disabled    = true
  user_assigned_identity_id = "/subscriptions/.../userAssignedIdentities/aksid-platform-prod-eus"

  default_nodepool_only_critical_addons_enabled = true
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
| [azurerm_kubernetes_cluster.aks_cluster](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/kubernetes_cluster) | resource |
| [azurerm_monitor_data_collection_rule_association.prometheus](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule_association) | resource |
| [azurerm_role_assignment.prometheus_publisher](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_definition.monitoring_metrics_publisher](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/role_definition) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | The Azure location where the AKS cluster will be deployed | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The resource group name where the AKS cluster will be created | `string` | n/a | yes |
| <a name="input_authorized_ip_ranges"></a> [authorized\_ip\_ranges](#input\_authorized\_ip\_ranges) | The IP ranges authorized for API server access | `list(string)` | `null` | no |
| <a name="input_automatic_channel_upgrade"></a> [automatic\_channel\_upgrade](#input\_automatic\_channel\_upgrade) | The upgrade channel for this Kubernetes Cluster. Possible values are patch, rapid, node-image and stable. | `string` | `"stable"` | no |
| <a name="input_azure_active_directory_role_based_access_control"></a> [azure\_active\_directory\_role\_based\_access\_control](#input\_azure\_active\_directory\_role\_based\_access\_control) | Azure Active Directory RBAC configuration for AKS | <pre>object({<br/>    admin_group_object_ids = list(string)<br/>    azure_rbac_enabled     = bool<br/>  })</pre> | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_create_kubeconfig"></a> [create\_kubeconfig](#input\_create\_kubeconfig) | Whether to create a local kubeconfig file | `bool` | `false` | no |
| <a name="input_default_nodepool_count"></a> [default\_nodepool\_count](#input\_default\_nodepool\_count) | Initial node count for the default node pool | `number` | `1` | no |
| <a name="input_default_nodepool_enable_auto_scaling"></a> [default\_nodepool\_enable\_auto\_scaling](#input\_default\_nodepool\_enable\_auto\_scaling) | Whether auto-scaling is enabled for the default node pool | `bool` | `true` | no |
| <a name="input_default_nodepool_max_count"></a> [default\_nodepool\_max\_count](#input\_default\_nodepool\_max\_count) | Maximum node count for the default node pool | `number` | `3` | no |
| <a name="input_default_nodepool_max_pods"></a> [default\_nodepool\_max\_pods](#input\_default\_nodepool\_max\_pods) | The maximum number of pods per node for the default node pool | `number` | `30` | no |
| <a name="input_default_nodepool_min_count"></a> [default\_nodepool\_min\_count](#input\_default\_nodepool\_min\_count) | Minimum node count for the default node pool | `number` | `1` | no |
| <a name="input_default_nodepool_name"></a> [default\_nodepool\_name](#input\_default\_nodepool\_name) | Name of the default node pool | `string` | `"system"` | no |
| <a name="input_default_nodepool_node_labels"></a> [default\_nodepool\_node\_labels](#input\_default\_nodepool\_node\_labels) | The node labels for the default node pool | `map(string)` | `{}` | no |
| <a name="input_default_nodepool_only_critical_addons_enabled"></a> [default\_nodepool\_only\_critical\_addons\_enabled](#input\_default\_nodepool\_only\_critical\_addons\_enabled) | Whether to taint the default node pool with CriticalAddonsOnly=true:NoSchedule to ensure only critical addons are scheduled on it | `bool` | `false` | no |
| <a name="input_default_nodepool_os_disk_size_gb"></a> [default\_nodepool\_os\_disk\_size\_gb](#input\_default\_nodepool\_os\_disk\_size\_gb) | OS disk size in GB for the default node pool | `number` | `128` | no |
| <a name="input_default_nodepool_vm_size"></a> [default\_nodepool\_vm\_size](#input\_default\_nodepool\_vm\_size) | VM size for the default node pool | `string` | `"Standard_D2s_v3"` | no |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | A list of diagnostic settings to create for the AKS cluster | <pre>list(object({<br/>    name                       = string<br/>    log_analytics_workspace_id = string<br/>    enabled_log_categories     = list(string)<br/>    metric_categories          = list(string)<br/>    log_retention_days         = optional(number)<br/>  }))</pre> | `[]` | no |
| <a name="input_dns_prefix"></a> [dns\_prefix](#input\_dns\_prefix) | DNS prefix for the AKS cluster | `string` | `null` | no |
| <a name="input_dns_service_ip"></a> [dns\_service\_ip](#input\_dns\_service\_ip) | The IP address for the DNS service | `string` | `"10.0.0.10"` | no |
| <a name="input_docker_bridge_cidr"></a> [docker\_bridge\_cidr](#input\_docker\_bridge\_cidr) | The CIDR for the Docker bridge network | `string` | `"172.17.0.1/16"` | no |
| <a name="input_enable_azure_policy"></a> [enable\_azure\_policy](#input\_enable\_azure\_policy) | Whether Azure Policy is enabled for the AKS cluster | `bool` | `true` | no |
| <a name="input_enable_host_encryption"></a> [enable\_host\_encryption](#input\_enable\_host\_encryption) | Whether host encryption is enabled for the AKS cluster | `bool` | `false` | no |
| <a name="input_enable_prometheus_integration"></a> [enable\_prometheus\_integration](#input\_enable\_prometheus\_integration) | Whether to enable the Azure Monitor managed service for Prometheus integration. | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name for resource tagging (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| <a name="input_identity_type"></a> [identity\_type](#input\_identity\_type) | The type of identity to use for the cluster | `string` | `"UserAssigned"` | no |
| <a name="input_kubernetes_version"></a> [kubernetes\_version](#input\_kubernetes\_version) | The Kubernetes version for the AKS cluster | `string` | `null` | no |
| <a name="input_local_account_disabled"></a> [local\_account\_disabled](#input\_local\_account\_disabled) | If true, disable local accounts in Kubernetes | `bool` | `true` | no |
| <a name="input_log_analytics_workspace_id"></a> [log\_analytics\_workspace\_id](#input\_log\_analytics\_workspace\_id) | The ID of the Log Analytics workspace for container insights | `string` | `null` | no |
| <a name="input_monitor_workspace_id"></a> [monitor\_workspace\_id](#input\_monitor\_workspace\_id) | The ID of the Azure Monitor Workspace where Prometheus metrics are sent. Required if enable\_prometheus\_integration is true. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the AKS cluster resource. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| <a name="input_network_plugin"></a> [network\_plugin](#input\_network\_plugin) | The network plugin to use for the AKS cluster | `string` | `"azure"` | no |
| <a name="input_network_policy"></a> [network\_policy](#input\_network\_policy) | The network policy to use for the AKS cluster | `string` | `null` | no |
| <a name="input_oidc_issuer_enabled"></a> [oidc\_issuer\_enabled](#input\_oidc\_issuer\_enabled) | Enable or disable the OIDC issuer URL | `bool` | `true` | no |
| <a name="input_outbound_type"></a> [outbound\_type](#input\_outbound\_type) | The outbound (egress) routing method for the AKS cluster | `string` | `"loadBalancer"` | no |
| <a name="input_pod_cidr"></a> [pod\_cidr](#input\_pod\_cidr) | The CIDR for pod IPs when using kubenet | `string` | `null` | no |
| <a name="input_private_cluster_enabled"></a> [private\_cluster\_enabled](#input\_private\_cluster\_enabled) | Whether the AKS cluster is a private cluster | `bool` | `false` | no |
| <a name="input_private_dns_zone_id"></a> [private\_dns\_zone\_id](#input\_private\_dns\_zone\_id) | The ID of the Private DNS Zone for private cluster | `string` | `null` | no |
| <a name="input_prometheus_dcr_id"></a> [prometheus\_dcr\_id](#input\_prometheus\_dcr\_id) | The ID of the Azure Monitor data collection rule for Prometheus metrics. If null and enable\_prometheus\_integration is true, integration will not be configured. | `string` | `null` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviation for region (used in resource naming) | `string` | `"weu"` | no |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A list of role assignments to create for the AKS cluster | <pre>list(object({<br/>    principal_id         = string<br/>    role_definition_name = string<br/>    description          = optional(string, null)<br/>  }))</pre> | `[]` | no |
| <a name="input_service_cidr"></a> [service\_cidr](#input\_service\_cidr) | The CIDR for Kubernetes services | `string` | `"10.0.0.0/16"` | no |
| <a name="input_sku_tier"></a> [sku\_tier](#input\_sku\_tier) | The SKU tier for the AKS cluster (Free or Standard) | `string` | `"Free"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The ID of the subnet where the AKS cluster will be deployed | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_user_assigned_identity_id"></a> [user\_assigned\_identity\_id](#input\_user\_assigned\_identity\_id) | The ID of the user-assigned identity for the AKS cluster | `string` | `null` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | `"platform"` | no |
| <a name="input_workload_identity_enabled"></a> [workload\_identity\_enabled](#input\_workload\_identity\_enabled) | Enable or disable Workload Identity for the cluster | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_certificate"></a> [client\_certificate](#output\_client\_certificate) | The client certificate for authentication |
| <a name="output_client_key"></a> [client\_key](#output\_client\_key) | The client key for authentication |
| <a name="output_cluster_ca_certificate"></a> [cluster\_ca\_certificate](#output\_cluster\_ca\_certificate) | The cluster CA certificate for communication with the cluster |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_default_node_pool_name"></a> [default\_node\_pool\_name](#output\_default\_node\_pool\_name) | The name of the default node pool |
| <a name="output_fqdn"></a> [fqdn](#output\_fqdn) | The FQDN of the AKS cluster |
| <a name="output_host"></a> [host](#output\_host) | The Kubernetes cluster server host |
| <a name="output_id"></a> [id](#output\_id) | The ID of the AKS cluster |
| <a name="output_identity"></a> [identity](#output\_identity) | The identity of the AKS cluster |
| <a name="output_kube_admin_config_raw"></a> [kube\_admin\_config\_raw](#output\_kube\_admin\_config\_raw) | The raw Kubernetes admin config to be used with kubectl and other tools |
| <a name="output_kube_config_raw"></a> [kube\_config\_raw](#output\_kube\_config\_raw) | The raw Kubernetes config to be used with kubectl and other tools |
| <a name="output_kubelet_identity"></a> [kubelet\_identity](#output\_kubelet\_identity) | The kubelet managed identity assigned to the AKS cluster |
| <a name="output_kubernetes_version"></a> [kubernetes\_version](#output\_kubernetes\_version) | The version of Kubernetes running on the AKS cluster |
| <a name="output_location"></a> [location](#output\_location) | The location/region of the AKS cluster |
| <a name="output_name"></a> [name](#output\_name) | The name of the AKS cluster |
| <a name="output_node_resource_group"></a> [node\_resource\_group](#output\_node\_resource\_group) | The name of the resource group containing the AKS cluster's node resources |
| <a name="output_node_resource_group_id"></a> [node\_resource\_group\_id](#output\_node\_resource\_group\_id) | The ID of the resource group containing the AKS cluster's node resources |
| <a name="output_oidc_issuer_url"></a> [oidc\_issuer\_url](#output\_oidc\_issuer\_url) | The OIDC issuer URL of the AKS cluster |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group that contains the AKS cluster |
<!-- END_TF_DOCS -->

## Notes

- When using `network_plugin = "none"` (BYOCNI), a CNI such as Cilium must be deployed before node groups can join the cluster. No kube-proxy DaemonSet is created in this mode.
- The default node pool is always created inline with the cluster. Use `default_nodepool_only_critical_addons_enabled` to taint it with `CriticalAddonsOnly` and schedule workloads on separate user node pools.
- Prometheus integration is enabled by default via `enable_prometheus_integration`. Supply `prometheus_dcr_id` and `monitor_workspace_id` for the DCR association to take effect.
- The module outputs `oidc_issuer_url` and `node_resource_group_id`, which are required inputs for the `identities` and `aks_identity` modules to create federated credentials and role assignments.
