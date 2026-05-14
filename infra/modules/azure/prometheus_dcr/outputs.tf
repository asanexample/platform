/**
 * Outputs for the Prometheus DCR module.
 */

output "dcr_id" {
  description = "The ID of the created Data Collection Rule."
  value       = var.create ? azurerm_monitor_data_collection_rule.this[0].id : null
}

output "dcr_name" {
  description = "The name of the created Data Collection Rule."
  value       = var.create ? azurerm_monitor_data_collection_rule.this[0].name : null
}

output "dce_id" {
  description = "The ID of the created Data Collection Endpoint."
  value       = var.create ? azurerm_monitor_data_collection_endpoint.this[0].id : null
}

output "dce_name" {
  description = "The name of the created Data Collection Endpoint."
  value       = var.create ? azurerm_monitor_data_collection_endpoint.this[0].name : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
} 