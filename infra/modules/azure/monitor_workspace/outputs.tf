/**
 * Outputs for the Azure Monitor Workspace module.
 */

output "id" {
  description = "The ID of the Azure Monitor Workspace."
  value       = azurerm_monitor_workspace.this.id
}

output "name" {
  description = "The name of the Azure Monitor Workspace."
  value       = azurerm_monitor_workspace.this.name
}

output "query_endpoint" {
  description = "The query endpoint for the Azure Monitor Workspace."
  value       = azurerm_monitor_workspace.this.query_endpoint
} 