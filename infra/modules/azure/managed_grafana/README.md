# Azure Managed Grafana Module

Creates an Azure Managed Grafana instance for visualizing metrics from Azure Monitor and Prometheus data sources.

## Usage

```hcl
module "managed_grafana" {
  source = "../managed_grafana"

  create = true

  resource_group_name    = "rg-platform-prod-eus"
  location               = "eastus"
  name                   = "grafana-platform-prod-eus"
  grafana_major_version  = "10"
  zone_redundancy_enabled = true

  prometheus_workspace_id = module.monitor_workspace.id

  admin_group_object_ids = ["11111111-1111-1111-1111-111111111111"]

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "managed_grafana" {
  source = "../managed_grafana"
  create = false
}
```

### Dev instance with public access

```hcl
module "managed_grafana" {
  source = "../managed_grafana"

  create = true

  resource_group_name           = "rg-platform-dev-eus"
  location                      = "eastus"
  name                          = "grafana-platform-dev-eus"
  grafana_major_version         = "10"
  zone_redundancy_enabled       = false
  api_key_enabled               = true
  public_network_access_enabled = true

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_dashboard_grafana.grafana](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dashboard_grafana) | resource |
| [azurerm_role_assignment.grafana_admin_groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.grafana_admin_users](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | The Azure region where the Grafana instance will be created | `string` | n/a | yes |
| resource_group_name | The name of the resource group where the Grafana instance will be created | `string` | n/a | yes |
| admin_group_object_ids | List of Microsoft Entra group Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| admin_user_object_ids | List of Microsoft Entra user Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| api_key_enabled | Whether to enable API key authentication for the Grafana instance | `bool` | `true` | no |
| auto_generated_domain_name_label_scope | The scope for the auto-generated domain name label | `string` | `"TenantReuse"` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| deterministic_outbound_ip_enabled | Whether to enable deterministic outbound IPs for the Grafana instance | `bool` | `false` | no |
| environment | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| grafana_major_version | The major version of Grafana to use | `string` | `"10"` | no |
| name | The name of the Azure Managed Grafana instance. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| workload | Workload name for resource names | `string` | `"platform"` | no |
| prometheus_workspace_id | The resource ID of the Azure Monitor workspace to integrate with Grafana | `string` | `null` | no |
| public_network_access_enabled | Whether to enable public network access for the Grafana instance | `bool` | `true` | no |
| region_abbv | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| tags | A mapping of tags to assign to the resource | `map(string)` | `{}` | no |
| zone_redundancy_enabled | Whether to enable zone redundancy for the Grafana instance | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| endpoint | The endpoint URL of the Azure Managed Grafana instance |
| grafana_version | The version of Grafana being used |
| id | The ID of the Azure Managed Grafana instance |
| identity | The identity of the Azure Managed Grafana instance |
| name | The name of the Azure Managed Grafana instance |
| resource_group_name | The name of the resource group where the Grafana instance is deployed |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) — Provides standardized resource names
- [resource_group](../resource_group) — Provides the resource group to deploy into
- [monitor_workspace](../monitor_workspace) — Provides the Prometheus workspace ID for metrics integration

## Notes

- Uses a system-assigned managed identity; ensure it has `Monitoring Reader` on connected Monitor Workspaces.
- Disable API keys in production (`api_key_enabled = false`).
- Enable zone redundancy in production for high availability.
