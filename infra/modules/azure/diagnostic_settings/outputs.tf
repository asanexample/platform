output "diagnostic_setting_ids" {
  description = "Map of diagnostic setting names to their resource IDs"
  value = {
    for k, v in azurerm_monitor_diagnostic_setting.this : k => v.id
  }
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
