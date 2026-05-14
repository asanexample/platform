/**
 * Outputs for the Azure Monitor Workspace module.
 */

output "id" {
  description = "The ID of the Azure Monitor Workspace."
  value       = var.create ? azurerm_monitor_workspace.this[0].id : null
}

output "name" {
  description = "The name of the Azure Monitor Workspace."
  value       = var.create ? azurerm_monitor_workspace.this[0].name : null
}

output "query_endpoint" {
  description = "The query endpoint for the Azure Monitor Workspace."
  value       = var.create ? azurerm_monitor_workspace.this[0].query_endpoint : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
} 