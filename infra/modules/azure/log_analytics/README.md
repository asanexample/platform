# Log Analytics

Creates an Azure Log Analytics workspace with optional solution packs (e.g., ContainerInsights) and role assignments. The workspace serves as the central log destination for AKS diagnostics, Key Vault audit logs, and other Azure resource telemetry. Supports configurable SKU, retention period, daily ingestion quota, and internet access controls.

## Usage

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                = "law-platform-dev-eus"
  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  retention_in_days   = 30
  sku                 = "PerGB2018"

  solution_plans = [
    { solution_name = "ContainerInsights" }
  ]

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"
  create = false
}
```

### With Role Assignments and Daily Quota

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                = "law-platform-prod-eus"
  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"
  retention_in_days   = 90
  daily_quota_gb      = 5

  solution_plans = [
    { solution_name = "ContainerInsights" },
    { solution_name = "KeyVaultAnalytics" }
  ]

  role_assignments = [
    {
      principal_id         = "00000000-0000-0000-0000-000000000000"
      role_definition_name = "Log Analytics Reader"
      description          = "Grafana read access"
    }
  ]
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
| [azurerm_log_analytics_solution.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_solution) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | The Azure region where the Log Analytics Workspace will be created | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group where the Log Analytics Workspace will be created | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_daily_quota_gb"></a> [daily\_quota\_gb](#input\_daily\_quota\_gb) | The workspace daily quota for ingestion in GB. Must be a positive number or null. | `number` | `null` | no |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | A list of diagnostic settings to create for the Log Analytics Workspace | <pre>list(object({<br/>    name                       = string<br/>    log_analytics_workspace_id = string<br/>    enabled_log_categories     = list(string)<br/>    metric_categories          = list(string)<br/>    log_retention_days         = number<br/>  }))</pre> | `[]` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment name (dev, prod, etc.) | `string` | `"dev"` | no |
| <a name="input_internet_ingestion_enabled"></a> [internet\_ingestion\_enabled](#input\_internet\_ingestion\_enabled) | Whether to enable internet ingestion for the Log Analytics Workspace | `bool` | `true` | no |
| <a name="input_internet_query_enabled"></a> [internet\_query\_enabled](#input\_internet\_query\_enabled) | Whether to enable internet query for the Log Analytics Workspace | `bool` | `true` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the Log Analytics Workspace. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | The abbreviated name of the Azure region | `string` | `"eus"` | no |
| <a name="input_retention_in_days"></a> [retention\_in\_days](#input\_retention\_in\_days) | The number of days to retain logs in the Log Analytics Workspace | `number` | `30` | no |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | A list of role assignments to create for the Log Analytics Workspace | <pre>list(object({<br/>    principal_id         = string<br/>    role_definition_name = string<br/>    description          = optional(string, null)<br/>  }))</pre> | `[]` | no |
| <a name="input_sku"></a> [sku](#input\_sku) | The SKU of the Log Analytics Workspace (PerGB2018, Free, PerNode, Premium, Standard, Standalone, Unlimited, or CapacityReservation) | `string` | `"PerGB2018"` | no |
| <a name="input_solution_plans"></a> [solution\_plans](#input\_solution\_plans) | A list of solution plans to install on the Log Analytics Workspace | <pre>list(object({<br/>    solution_name = string<br/>    publisher     = optional(string, "Microsoft")<br/>    product       = optional(string, null)<br/>  }))</pre> | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to apply to the Log Analytics Workspace | `map(string)` | `{}` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | The workload identifier to apply to resource names | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_id"></a> [id](#output\_id) | The ID of the Log Analytics Workspace |
| <a name="output_name"></a> [name](#output\_name) | The name of the Log Analytics Workspace |
| <a name="output_primary_shared_key"></a> [primary\_shared\_key](#output\_primary\_shared\_key) | The primary shared key for the Log Analytics Workspace |
| <a name="output_secondary_shared_key"></a> [secondary\_shared\_key](#output\_secondary\_shared\_key) | The secondary shared key for the Log Analytics Workspace |
| <a name="output_solutions"></a> [solutions](#output\_solutions) | The solutions installed on the Log Analytics Workspace |
| <a name="output_workspace_id"></a> [workspace\_id](#output\_workspace\_id) | The workspace ID for the Log Analytics Workspace |
<!-- END_TF_DOCS -->

## Notes

- The default SKU `PerGB2018` is the most common pay-as-you-go pricing model. Retention must be between 30 and 730 days.
- Solution packs are deployed as `azurerm_log_analytics_solution` resources. Valid names include `ContainerInsights`, `KeyVaultAnalytics`, `Security`, and others listed in the variable validation.
- The `daily_quota_gb` setting can prevent runaway costs from high log volumes. Set to `null` for unlimited ingestion.
- Internet ingestion and query are both enabled by default. Disable them for fully private workspace access.
