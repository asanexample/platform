/**
 * # Log Analytics Outputs
 * 
 * Outputs for the Azure Log Analytics module
 */

output "id" {
  description = "The ID of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.id
}

output "name" {
  description = "The name of the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.name
}

output "primary_shared_key" {
  description = "The primary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.primary_shared_key
  sensitive   = true
}

output "secondary_shared_key" {
  description = "The secondary shared key for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.secondary_shared_key
  sensitive   = true
}

output "workspace_id" {
  description = "The workspace ID for the Log Analytics workspace"
  value       = azurerm_log_analytics_workspace.this.workspace_id
}

output "solution_ids" {
  description = "The IDs of the deployed Log Analytics solutions"
  value = {
    for name, solution in azurerm_log_analytics_solution.this : name => solution.id
  }
}

output "diagnostic_settings" {
  description = "The diagnostic settings created for the Log Analytics workspace"
  value = {
    for idx, setting in azurerm_monitor_diagnostic_setting.this : idx => {
      id   = setting.id
      name = setting.name
    }
  }
}

output "linked_storage_accounts" {
  description = "The linked storage accounts for the Log Analytics workspace"
  value = {
    for type, account in azurerm_log_analytics_linked_storage_account.this : type => account.id
  }
} 