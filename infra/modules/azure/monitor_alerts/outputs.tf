output "action_group_ids" {
  description = "Map of action group names to their resource IDs"
  value = {
    for k, v in azurerm_monitor_action_group.this : k => v.id
  }
}

output "metric_alert_ids" {
  description = "Map of metric alert names to their resource IDs"
  value = {
    for k, v in azurerm_monitor_metric_alert.this : k => v.id
  }
}

output "activity_log_alert_ids" {
  description = "Map of activity log alert names to their resource IDs"
  value = {
    for k, v in azurerm_monitor_activity_log_alert.this : k => v.id
  }
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
