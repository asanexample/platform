# Monitor Alerts

Creates Azure Monitor action groups, metric alerts, and activity log alerts. Action groups define notification targets (email, webhook) and are referenced by alerts via key names. Metric alerts evaluate resource metrics against thresholds with configurable severity, frequency, and dimensions. Activity log alerts monitor control plane operations and service health events. All resource names include the workload, environment, and region suffix.

## Usage

```hcl
module "monitor_alerts" {
  source = "../../modules/azure/monitor_alerts"

  resource_group_name = "rg-platform-dev-eus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"

  action_groups = {
    "platform-ops" = {
      short_name = "platops"
      email_receivers = [
        {
          name          = "ops-team"
          email_address = "ops@example.com"
        }
      ]
    }
  }

  metric_alerts = {
    "aks-cpu-high" = {
      scopes            = ["/subscriptions/.../managedClusters/aks-platform-dev-eus"]
      severity          = 2
      action_group_keys = ["platform-ops"]
      criteria = [
        {
          metric_namespace = "Microsoft.ContainerService/managedClusters"
          metric_name      = "node_cpu_usage_percentage"
          aggregation      = "Average"
          operator         = "GreaterThan"
          threshold        = 80
        }
      ]
    }
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
module "monitor_alerts" {
  source = "../../modules/azure/monitor_alerts"
  create = false
}
```

### Activity Log Alert for Service Health

```hcl
module "monitor_alerts" {
  source = "../../modules/azure/monitor_alerts"

  resource_group_name = "rg-platform-prod-eus"
  workload            = "platform"
  environment         = "prod"
  region_abbv         = "eus"

  action_groups = {
    "oncall" = {
      short_name = "oncall"
      webhook_receivers = [
        {
          name        = "pagerduty"
          service_uri = "https://events.pagerduty.com/integration/..."
        }
      ]
    }
  }

  activity_log_alerts = {
    "service-health" = {
      scopes            = ["/subscriptions/00000000-0000-0000-0000-000000000000"]
      action_group_keys = ["oncall"]
      criteria = {
        category = "ServiceHealth"
        service_health = {
          events    = ["Incident", "Maintenance"]
          locations = ["East US"]
        }
      }
    }
  }
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
| [azurerm_monitor_action_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_action_group) | resource |
| [azurerm_monitor_activity_log_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_activity_log_alert) | resource |
| [azurerm_monitor_metric_alert.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_metric_alert) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name | `string` | n/a | yes |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviated Azure region name | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The resource group to deploy alert resources into | `string` | n/a | yes |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource naming | `string` | n/a | yes |
| <a name="input_action_groups"></a> [action\_groups](#input\_action\_groups) | Action groups for alert routing | <pre>map(object({<br/>    short_name = string<br/>    enabled    = optional(bool, true)<br/><br/>    email_receivers = optional(list(object({<br/>      name                    = string<br/>      email_address           = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), [])<br/><br/>    webhook_receivers = optional(list(object({<br/>      name                    = string<br/>      service_uri             = string<br/>      use_common_alert_schema = optional(bool, true)<br/>    })), [])<br/>  }))</pre> | `{}` | no |
| <a name="input_activity_log_alerts"></a> [activity\_log\_alerts](#input\_activity\_log\_alerts) | Activity log alert rules for service health and resource operations | <pre>map(object({<br/>    description       = optional(string, "")<br/>    enabled           = optional(bool, true)<br/>    scopes            = list(string)<br/>    action_group_keys = list(string)<br/><br/>    criteria = object({<br/>      category       = string<br/>      operation_name = optional(string, null)<br/>      level          = optional(string, null)<br/>      status         = optional(string, null)<br/>      resource_type  = optional(string, null)<br/><br/>      service_health = optional(object({<br/>        events    = optional(list(string), ["Incident", "Maintenance"])<br/>        locations = optional(list(string), [])<br/>        services  = optional(list(string), [])<br/>      }), null)<br/>    })<br/>  }))</pre> | `{}` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_location"></a> [location](#input\_location) | Azure region (used only for resource group reference, alerts are global) | `string` | `"global"` | no |
| <a name="input_metric_alerts"></a> [metric\_alerts](#input\_metric\_alerts) | Metric-based alert rules | <pre>map(object({<br/>    description       = optional(string, "")<br/>    severity          = optional(number, 2)<br/>    enabled           = optional(bool, true)<br/>    scopes            = list(string)<br/>    frequency         = optional(string, "PT5M")<br/>    window_size       = optional(string, "PT15M")<br/>    action_group_keys = list(string)<br/>    auto_mitigate     = optional(bool, true)<br/><br/>    criteria = list(object({<br/>      metric_namespace = string<br/>      metric_name      = string<br/>      aggregation      = string<br/>      operator         = string<br/>      threshold        = number<br/>      dimension = optional(list(object({<br/>        name     = string<br/>        operator = string<br/>        values   = list(string)<br/>      })), [])<br/>    }))<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_action_group_ids"></a> [action\_group\_ids](#output\_action\_group\_ids) | Map of action group names to their resource IDs |
| <a name="output_activity_log_alert_ids"></a> [activity\_log\_alert\_ids](#output\_activity\_log\_alert\_ids) | Map of activity log alert names to their resource IDs |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_metric_alert_ids"></a> [metric\_alert\_ids](#output\_metric\_alert\_ids) | Map of metric alert names to their resource IDs |
<!-- END_TF_DOCS -->

## Notes

- Action groups are referenced by their map key in `action_group_keys` on alerts. The action group short name must be 12 characters or less.
- Metric alert severity levels: 0 = Critical, 1 = Error, 2 = Warning, 3 = Informational, 4 = Verbose.
- Activity log alerts are always created with `location = "global"` regardless of the `location` variable, as activity log data is not region-specific.
- Alert names are suffixed with `{workload}-{environment}-{region_abbv}` for uniqueness across environments.
