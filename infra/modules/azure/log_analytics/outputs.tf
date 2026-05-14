/**
 * Output variables for the Log Analytics Workspace module
 */

output "id" {
  description = "The ID of the Log Analytics Workspace"
  value       = var.create ? azurerm_log_analytics_workspace.this[0].id : null
}

output "name" {
  description = "The name of the Log Analytics Workspace"
  value       = var.create ? azurerm_log_analytics_workspace.this[0].name : null
}

output "primary_shared_key" {
  description = "The primary shared key for the Log Analytics Workspace"
  value       = var.create ? azurerm_log_analytics_workspace.this[0].primary_shared_key : null
  sensitive   = true
}

output "secondary_shared_key" {
  description = "The secondary shared key for the Log Analytics Workspace"
  value       = var.create ? azurerm_log_analytics_workspace.this[0].secondary_shared_key : null
  sensitive   = true
}

output "workspace_id" {
  description = "The workspace ID for the Log Analytics Workspace"
  value       = var.create ? azurerm_log_analytics_workspace.this[0].workspace_id : null
}

output "solutions" {
  description = "The solutions installed on the Log Analytics Workspace"
  value       = var.create ? [for solution in azurerm_log_analytics_solution.this : solution.solution_name] : []
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
} 