# Azure Naming Module

Generates standardized Azure resource names following organizational conventions and Azure naming restrictions.

## Usage

```hcl
module "naming" {
  source = "../naming"

  workload    = "platform"
  environment = "dev"
  region_abbv = "eus"
}

# Reference generated names
resource "azurerm_resource_group" "this" {
  name     = module.naming.resource_group
  location = "eastus"
}
```

## Examples

### Shared (non-customer) resources

```hcl
module "naming" {
  source = "../naming"

  workload    = "platform"
  environment = "ops"
  region_abbv = "wus"
}
```

<!-- BEGIN_TF_DOCS -->


## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | The environment (e.g., dev, preprod, prod, ops). | `string` | n/a | yes |
| region_abbv | The abbreviated Azure region name (e.g., wus, eus, neu). | `string` | n/a | yes |
| custom_name | Optional custom name to override the generated name. | `string` | `null` | no |
| workload | The workload name to use for all resources. Defaults to 'platform' if not specified. | `string` | `"platform"` | no |
| resource_type | Optional resource type for custom naming. | `string` | `null` | no |
| unique_seed | Seed for unique naming generation | `string` | `""` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| aks_cluster | Standardized name for an Azure Kubernetes Service cluster. |
| aks_identity | Standardized name for an AKS managed identity. |
| aks_node_pool | Standardized name for an AKS node pool. |
| app_configuration | Standardized name for an App Configuration. |
| app_service | Standardized name for an App Service. |
| application_insights | Standardized name for Application Insights. |
| bastion_host | Standardized name for a Bastion Host. |
| container_insights | Standardized name for an AKS container insights resource. |
| container_registry | Standardized name for a Container Registry. |
| cosmos_account | Standardized name for a Cosmos DB Account. |
| event_hub | Standardized name for an Event Hub. |
| event_hub_namespace | Standardized name for an Event Hub Namespace. |
| federated_identity | Standardized name for a federated identity. |
| front_door | Standardized name for a Front Door. |
| frontdoor_endpoint | Standardized name for a Front Door Endpoint. |
| frontdoor_origin | Standardized name for a Front Door Origin. |
| frontdoor_origin_group | Standardized name for a Front Door Origin Group. |
| frontdoor_profile | Standardized name for a Front Door Profile. |
| frontdoor_route | Standardized name for a Front Door Route. |
| function_app | Standardized name for a Function App. |
| grafana | The generated name for the Azure Grafana instance |
| key_vault | Standardized name for an Azure Key Vault. |
| load_balancer | Standardized name for a Load Balancer. |
| log_analytics_workspace | Standardized name for a Log Analytics Workspace. |
| managed_prometheus | Standardized name for an AKS managed Prometheus resource. |
| monitor_workspace | The generated name for the Azure Monitor workspace (Prometheus) |
| names | Map of all generated resource names. |
| network_security_group | Standardized name for a Network Security Group. |
| normalized_customer | Normalized customer name for use in resource naming. |
| private_endpoint | Standardized name for a Private Endpoint. |
| public_ip | Standardized name for a Public IP. |
| resource_group | Standardized name for an Azure Resource Group. |
| resource_types | All resource type abbreviations. |
| route_table | Standardized name for a Route Table. |
| sql_database | Standardized name for a SQL Database. |
| sql_server | Standardized name for a SQL Server. |
| storage_account | Standardized name for an Azure Storage Account. |
| subnet | Function to generate standardized subnet names with subnet type parameter. |
| subnet_api | Standardized name for an API subnet. |
| subnet_app | Standardized name for an application subnet. |
| subnet_db | Standardized name for a database subnet. |
| subnet_endpoint | Standardized name for a private endpoint subnet. |
| subnet_gateway | Standardized name for a gateway subnet. |
| subnet_node | Standardized name for a node subnet. |
| subnet_service | Standardized name for a service subnet. |
| subnet_with_type | Generate a subnet name with a specific type. |
| virtual_network | Standardized name for a Virtual Network. |
| workload_identity | Standardized name for a workload identity. |
<!-- END_TF_DOCS -->

## Dependencies

None -- this is a data-only module that other modules depend on.

## Notes

- This module has no `create` variable; it is a data-only module that always produces outputs.
- Storage account and container registry names have special formatting (no hyphens, character limits) handled automatically.
- When `customer` is omitted, the customer segment is excluded from generated names.
