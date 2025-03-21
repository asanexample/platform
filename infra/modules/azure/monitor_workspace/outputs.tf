output "id" {
  description = "The ID of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.prometheus.id
}

output "name" {
  description = "The name of the Azure Monitor workspace"
  value       = azurerm_monitor_workspace.prometheus.name
}

output "dcr_id" {
  description = "The ID of the Data Collection Rule"
  value       = azurerm_monitor_data_collection_rule.prometheus.id
}

output "dce_id" {
  description = "The ID of the Data Collection Endpoint"
  value       = azurerm_monitor_data_collection_endpoint.prometheus.id
} 