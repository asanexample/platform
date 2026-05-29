# Naming

Generates standardized resource names for all Azure resource types following Cloud Adoption Framework (CAF) conventions. Names follow the pattern `{type}-{workload}-{environment}-{region}` for hyphen-separated resources and `{type}{abbreviated_workload}{environment}{region}` for resources that prohibit hyphens (storage accounts, container registries, AKS node pools). Names are validated against Azure length and character constraints and truncated if necessary. This module creates no Azure resources.

## Usage

```hcl
module "naming" {
  source = "../../modules/azure/naming"

  workload    = "platform"
  environment = "dev"
  region_abbv = "eus"
}

# Then reference outputs:
# module.naming.resource_group       => "rg-platform-dev-eus"
# module.naming.aks_cluster          => "aks-platform-dev-eus"
# module.naming.storage_account      => "stplatdeveus"
# module.naming.key_vault            => "kv-plat-dev-eus"
# module.naming.container_registry   => "acrplatdeveus"
# module.naming.log_analytics_workspace => "law-platform-dev-eus"
# module.naming.subnet_node          => "snet-platform-dev-node-eus"
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

No providers.

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_grafana"></a> [grafana](#module\_grafana) | Azure/naming/azurerm | n/a |
| <a name="module_monitor_workspace"></a> [monitor\_workspace](#module\_monitor\_workspace) | Azure/naming/azurerm | n/a |

## Resources

No resources.

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment (e.g., dev, preprod, prod, ops). | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | The abbreviated Azure region name (e.g., wus, eus, neu). | `string` | n/a | yes |
| <a name="input_custom_name"></a> [custom\_name](#input\_custom\_name) | Optional custom name to override the generated name. | `string` | `null` | no |
| <a name="input_resource_type"></a> [resource\_type](#input\_resource\_type) | Optional resource type for custom naming. | `string` | `null` | no |
| <a name="input_unique_seed"></a> [unique\_seed](#input\_unique\_seed) | Seed for unique naming generation | `string` | `""` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | The workload identifier used in resource naming (e.g., platform, data, hipaa, pci). | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_action_group"></a> [action\_group](#output\_action\_group) | Standardized name for an Azure Monitor Action Group. |
| <a name="output_activity_log_alert"></a> [activity\_log\_alert](#output\_activity\_log\_alert) | Standardized name for an Azure Monitor Activity Log Alert. |
| <a name="output_aks_cluster"></a> [aks\_cluster](#output\_aks\_cluster) | Standardized name for an Azure Kubernetes Service cluster. |
| <a name="output_aks_identity"></a> [aks\_identity](#output\_aks\_identity) | Standardized name for an AKS managed identity. |
| <a name="output_aks_node_pool"></a> [aks\_node\_pool](#output\_aks\_node\_pool) | Standardized name for an AKS node pool. |
| <a name="output_app_configuration"></a> [app\_configuration](#output\_app\_configuration) | Standardized name for an App Configuration. |
| <a name="output_app_service"></a> [app\_service](#output\_app\_service) | Standardized name for an App Service. |
| <a name="output_application_insights"></a> [application\_insights](#output\_application\_insights) | Standardized name for Application Insights. |
| <a name="output_bastion_host"></a> [bastion\_host](#output\_bastion\_host) | Standardized name for a Bastion Host. |
| <a name="output_container_insights"></a> [container\_insights](#output\_container\_insights) | Standardized name for an AKS container insights resource. |
| <a name="output_container_registry"></a> [container\_registry](#output\_container\_registry) | Standardized name for a Container Registry. |
| <a name="output_cosmos_account"></a> [cosmos\_account](#output\_cosmos\_account) | Standardized name for a Cosmos DB Account. |
| <a name="output_diagnostic_setting"></a> [diagnostic\_setting](#output\_diagnostic\_setting) | Standardized name for an Azure Diagnostic Setting. |
| <a name="output_event_hub"></a> [event\_hub](#output\_event\_hub) | Standardized name for an Event Hub. |
| <a name="output_event_hub_namespace"></a> [event\_hub\_namespace](#output\_event\_hub\_namespace) | Standardized name for an Event Hub Namespace. |
| <a name="output_federated_identity"></a> [federated\_identity](#output\_federated\_identity) | Standardized name for a federated identity. |
| <a name="output_front_door"></a> [front\_door](#output\_front\_door) | Standardized name for a Front Door. |
| <a name="output_frontdoor_endpoint"></a> [frontdoor\_endpoint](#output\_frontdoor\_endpoint) | Standardized name for a Front Door Endpoint. |
| <a name="output_frontdoor_origin"></a> [frontdoor\_origin](#output\_frontdoor\_origin) | Standardized name for a Front Door Origin. |
| <a name="output_frontdoor_origin_group"></a> [frontdoor\_origin\_group](#output\_frontdoor\_origin\_group) | Standardized name for a Front Door Origin Group. |
| <a name="output_frontdoor_profile"></a> [frontdoor\_profile](#output\_frontdoor\_profile) | Standardized name for a Front Door Profile. |
| <a name="output_frontdoor_route"></a> [frontdoor\_route](#output\_frontdoor\_route) | Standardized name for a Front Door Route. |
| <a name="output_function_app"></a> [function\_app](#output\_function\_app) | Standardized name for a Function App. |
| <a name="output_grafana"></a> [grafana](#output\_grafana) | Standardized name for an Azure Managed Grafana instance. |
| <a name="output_key_vault"></a> [key\_vault](#output\_key\_vault) | Standardized name for an Azure Key Vault. |
| <a name="output_load_balancer"></a> [load\_balancer](#output\_load\_balancer) | Standardized name for a Load Balancer. |
| <a name="output_log_analytics_workspace"></a> [log\_analytics\_workspace](#output\_log\_analytics\_workspace) | Standardized name for a Log Analytics Workspace. |
| <a name="output_managed_prometheus"></a> [managed\_prometheus](#output\_managed\_prometheus) | Standardized name for an AKS managed Prometheus resource. |
| <a name="output_metric_alert"></a> [metric\_alert](#output\_metric\_alert) | Standardized name for an Azure Monitor Metric Alert. |
| <a name="output_monitor_workspace"></a> [monitor\_workspace](#output\_monitor\_workspace) | Standardized name for an Azure Monitor workspace (Prometheus). |
| <a name="output_names"></a> [names](#output\_names) | Map of all generated resource names. |
| <a name="output_network_security_group"></a> [network\_security\_group](#output\_network\_security\_group) | Standardized name for a Network Security Group. |
| <a name="output_private_endpoint"></a> [private\_endpoint](#output\_private\_endpoint) | Standardized name for a Private Endpoint. |
| <a name="output_public_ip"></a> [public\_ip](#output\_public\_ip) | Standardized name for a Public IP. |
| <a name="output_resource_group"></a> [resource\_group](#output\_resource\_group) | Standardized name for an Azure Resource Group. |
| <a name="output_resource_types"></a> [resource\_types](#output\_resource\_types) | All resource type abbreviations. |
| <a name="output_route_table"></a> [route\_table](#output\_route\_table) | Standardized name for a Route Table. |
| <a name="output_sql_database"></a> [sql\_database](#output\_sql\_database) | Standardized name for a SQL Database. |
| <a name="output_sql_server"></a> [sql\_server](#output\_sql\_server) | Standardized name for a SQL Server. |
| <a name="output_storage_account"></a> [storage\_account](#output\_storage\_account) | Standardized name for an Azure Storage Account. |
| <a name="output_subnet"></a> [subnet](#output\_subnet) | Base subnet name for generating type-specific subnet names. |
| <a name="output_subnet_api"></a> [subnet\_api](#output\_subnet\_api) | Standardized name for an API subnet. |
| <a name="output_subnet_app"></a> [subnet\_app](#output\_subnet\_app) | Standardized name for an application subnet. |
| <a name="output_subnet_db"></a> [subnet\_db](#output\_subnet\_db) | Standardized name for a database subnet. |
| <a name="output_subnet_endpoint"></a> [subnet\_endpoint](#output\_subnet\_endpoint) | Standardized name for a private endpoint subnet. |
| <a name="output_subnet_gateway"></a> [subnet\_gateway](#output\_subnet\_gateway) | Standardized name for a gateway subnet. |
| <a name="output_subnet_node"></a> [subnet\_node](#output\_subnet\_node) | Standardized name for a node subnet. |
| <a name="output_subnet_service"></a> [subnet\_service](#output\_subnet\_service) | Standardized name for a service subnet. |
| <a name="output_subnet_with_type"></a> [subnet\_with\_type](#output\_subnet\_with\_type) | Base subnet name for appending custom type suffixes. |
| <a name="output_virtual_network"></a> [virtual\_network](#output\_virtual\_network) | Standardized name for a Virtual Network. |
| <a name="output_workload_identity"></a> [workload\_identity](#output\_workload\_identity) | Standardized name for a workload identity. |
<!-- END_TF_DOCS -->

## Notes

- Workloads longer than 4 characters are abbreviated for tight-constraint resources (Key Vault, storage accounts). Known abbreviations: `platform` -> `plat`, `connectivity` -> `conn`, `shared` -> `shrd`.
- The module uses the `Azure/naming/azurerm` community module internally for monitor workspace and Grafana naming.
- All outputs are available in `module.naming.names` as a single map, or individually (e.g., `module.naming.aks_cluster`, `module.naming.resource_group`).
- Subnet outputs include purpose-specific variants: `subnet_node`, `subnet_api`, `subnet_app`, `subnet_db`, `subnet_endpoint`, `subnet_service`, `subnet_gateway`.
- The `resource_types` output exposes all type abbreviation mappings for custom naming logic.
