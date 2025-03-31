/**
 * Output variables for the Log Analytics Workspace module
 */

output "id" {
  description = "The ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.id
}

output "name" {
  description = "The name of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.name
}

output "primary_shared_key" {
  description = "The primary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

output "secondary_shared_key" {
  description = "The secondary shared key for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.secondary_shared_key
  sensitive   = true
}

output "workspace_id" {
  description = "The workspace ID for the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "solutions" {
  description = "The solutions installed on the Log Analytics Workspace"
  value       = [for solution in azurerm_log_analytics_solution.this : solution.solution_name]
} 