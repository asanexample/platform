/**
 * # Container Insights DCR Outputs
 *
 * Outputs for the Container Insights DCR Module.
 */

output "id" {
  description = "The ID of the Container Insights DCR"
  value       = azurerm_monitor_data_collection_rule.container_insights.id
}

output "name" {
  description = "The name of the Container Insights DCR"
  value       = azurerm_monitor_data_collection_rule.container_insights.name
}

output "association_id" {
  description = "The ID of the DCR association"
  value       = azurerm_monitor_data_collection_rule_association.container_insights.id
} 