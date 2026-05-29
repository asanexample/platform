# Diagnostic Settings

Creates Azure Monitor diagnostic settings that route logs and metrics from target resources to a Log Analytics workspace. Each setting is defined as a map entry specifying the target resource, destination workspace, and which log categories, log category groups, and metric categories to enable. This module supports any Azure resource that exposes diagnostic settings.

## Usage

```hcl
module "diagnostic_settings" {
  source = "../../modules/azure/diagnostic_settings"

  diagnostic_settings = {
    "aks-diagnostics" = {
      target_resource_id         = "/subscriptions/.../managedClusters/aks-platform-dev-eus"
      log_analytics_workspace_id = "/subscriptions/.../workspaces/law-platform-dev-eus"
      enabled_log_categories     = ["kube-apiserver", "kube-controller-manager"]
      log_category_groups        = []
      metric_categories          = ["AllMetrics"]
    }
    "keyvault-diagnostics" = {
      target_resource_id         = "/subscriptions/.../vaults/kv-plat-dev-eus"
      log_analytics_workspace_id = "/subscriptions/.../workspaces/law-platform-dev-eus"
      enabled_log_categories     = []
      log_category_groups        = ["allLogs"]
      metric_categories          = ["AllMetrics"]
    }
  }
}
```

## Examples

### Disabled Module

```hcl
module "diagnostic_settings" {
  source = "../../modules/azure/diagnostic_settings"
  create = false
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
| [azurerm_monitor_diagnostic_setting.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_diagnostic_setting) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_diagnostic_settings"></a> [diagnostic\_settings](#input\_diagnostic\_settings) | Map of diagnostic settings to create. Each routes logs/metrics from a target resource to Log Analytics. | <pre>map(object({<br/>    target_resource_id         = string<br/>    log_analytics_workspace_id = string<br/><br/>    enabled_log_categories = optional(list(string), [])<br/><br/>    log_category_groups = optional(list(string), [])<br/><br/>    metric_categories = optional(list(string), [])<br/><br/>    log_analytics_destination_type = optional(string, null)<br/>  }))</pre> | `{}` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags (not applied to diagnostic settings directly, reserved for future use) | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_diagnostic_setting_ids"></a> [diagnostic\_setting\_ids](#output\_diagnostic\_setting\_ids) | Map of diagnostic setting names to their resource IDs |
<!-- END_TF_DOCS -->

## Notes

- Each map key becomes the diagnostic setting name in Azure. Both `target_resource_id` and `log_analytics_workspace_id` are required for every entry.
- Use `enabled_log_categories` for individual log categories (e.g., `kube-apiserver`) or `log_category_groups` for groups (e.g., `allLogs`). Both can be specified on the same setting.
- The `tags` variable is accepted but not applied to diagnostic settings directly, since Azure diagnostic settings do not support tags.
