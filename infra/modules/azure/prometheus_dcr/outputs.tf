/**
 * Outputs for the Prometheus DCR module.
 */

output "dcr_id" {
  description = "The ID of the created Data Collection Rule."
  value       = azurerm_monitor_data_collection_rule.this.id
}

output "dcr_name" {
  description = "The name of the created Data Collection Rule."
  value       = azurerm_monitor_data_collection_rule.this.name
}

output "dce_id" {
  description = "The ID of the created Data Collection Endpoint."
  value       = azurerm_monitor_data_collection_endpoint.this.id
}

output "dce_name" {
  description = "The name of the created Data Collection Endpoint."
  value       = azurerm_monitor_data_collection_endpoint.this.name
} 