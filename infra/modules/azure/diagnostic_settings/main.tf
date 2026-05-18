resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each = var.create ? var.diagnostic_settings : {}

  name                           = each.key
  target_resource_id             = each.value.target_resource_id
  log_analytics_workspace_id     = each.value.log_analytics_workspace_id
  log_analytics_destination_type = each.value.log_analytics_destination_type

  dynamic "enabled_log" {
    for_each = toset(each.value.enabled_log_categories)
    content {
      category = enabled_log.value
    }
  }

  dynamic "enabled_log" {
    for_each = toset(each.value.log_category_groups)
    content {
      category_group = enabled_log.value
    }
  }

  dynamic "metric" {
    for_each = toset(each.value.metric_categories)
    content {
      category = metric.value
      enabled  = true
    }
  }
}
