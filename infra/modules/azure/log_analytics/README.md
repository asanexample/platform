# Azure Log Analytics Module

Creates a Log Analytics workspace with optional solution packs, diagnostic settings, and role assignments for centralized logging and monitoring.

## Usage

```hcl
module "log_analytics" {
  source = "../log_analytics"

  create = true

  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"
  name                = "law-platform-prod-eus"
  sku                 = "PerGB2018"
  retention_in_days   = 90

  solution_plans = [
    { solution_name = "ContainerInsights" },
    { solution_name = "Security" }
  ]

  role_assignments = [
    {
      principal_id         = data.azuread_group.platform_team.id
      role_definition_name = "Log Analytics Contributor"
      description          = "Platform team workspace access"
    }
  ]

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "log_analytics" {
  source = "../log_analytics"
  create = false
}
```

### Minimal dev workspace

```hcl
module "log_analytics" {
  source = "../log_analytics"

  create = true

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  name                = "law-platform-dev-eus"
  retention_in_days   = 30

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
| [azurerm_log_analytics_solution.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_solution) | resource |
| [azurerm_log_analytics_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/log_analytics_workspace) | resource |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | The Azure region where the Log Analytics Workspace will be created | `string` | n/a | yes |
| resource_group_name | The name of the resource group where the Log Analytics Workspace will be created | `string` | n/a | yes |
| create | Whether to create resources in this module | `bool` | `true` | no |
| daily_quota_gb | The workspace daily quota for ingestion in GB. Must be a positive number or null. | `number` | `null` | no |
| diagnostic_settings | A list of diagnostic settings to create for the Log Analytics Workspace | <pre>list(object({<br/>    name                       = string<br/>    log_analytics_workspace_id = string<br/>    enabled_log_categories     = list(string)<br/>    metric_categories          = list(string)<br/>    log_retention_days         = number<br/>  }))</pre> | `[]` | no |
| environment | The environment name (dev, prod, etc.) | `string` | `"dev"` | no |
| internet_ingestion_enabled | Whether to enable internet ingestion for the Log Analytics Workspace | `bool` | `true` | no |
| internet_query_enabled | Whether to enable internet query for the Log Analytics Workspace | `bool` | `true` | no |
| name | The name of the Log Analytics Workspace. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| workload | The workload name to apply to resource names | `string` | `"platform"` | no |
| region_abbv | The abbreviated name of the Azure region | `string` | `"eus"` | no |
| retention_in_days | The number of days to retain logs in the Log Analytics Workspace | `number` | `30` | no |
| role_assignments | A list of role assignments to create for the Log Analytics Workspace | <pre>list(object({<br/>    principal_id   = string<br/>    role_definition_name = string<br/>    description    = optional(string, null)<br/>  }))</pre> | `[]` | no |
| sku | The SKU of the Log Analytics Workspace (PerGB2018, Free, PerNode, Premium, Standard, Standalone, Unlimited, or CapacityReservation) | `string` | `"PerGB2018"` | no |
| solution_plans | A list of solution plans to install on the Log Analytics Workspace | <pre>list(object({<br/>    solution_name = string<br/>    publisher     = optional(string, "Microsoft")<br/>    product       = optional(string, null)<br/>  }))</pre> | `[]` | no |
| tags | A map of tags to apply to the Log Analytics Workspace | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| id | The ID of the Log Analytics Workspace |
| name | The name of the Log Analytics Workspace |
| primary_shared_key | The primary shared key for the Log Analytics Workspace |
| secondary_shared_key | The secondary shared key for the Log Analytics Workspace |
| solutions | The solutions installed on the Log Analytics Workspace |
| workspace_id | The workspace ID for the Log Analytics Workspace |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) — Provides standardized resource names
- [resource_group](../resource_group) — Provides the resource group to deploy into

## Notes

- `daily_quota_gb` helps control costs but data is dropped once the quota is hit for the day.
- Log retention must be between 30 and 730 days.
