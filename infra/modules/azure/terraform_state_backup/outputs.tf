/**
 * # Terraform State Backup Module - Outputs
 *
 * Output values for the Terraform state backup module.
 */

output "backup_storage_account_id" {
  description = "The resource ID of the backup storage account"
  value       = azurerm_storage_account.backup.id
}

output "backup_storage_account_name" {
  description = "The name of the backup storage account"
  value       = azurerm_storage_account.backup.name
}

output "backup_container_name" {
  description = "The name of the backup storage container"
  value       = azurerm_storage_container.backup.name
}

output "backup_function_id" {
  description = "The resource ID of the backup function app"
  value       = azurerm_linux_function_app.backup_function.id
}

output "backup_function_name" {
  description = "The name of the backup function app"
  value       = azurerm_linux_function_app.backup_function.name
}

output "backup_function_identity_id" {
  description = "The ID of the managed identity used by the backup function"
  value       = azurerm_user_assigned_identity.backup_function.id
}

output "backup_function_identity_principal_id" {
  description = "The principal ID of the managed identity used by the backup function"
  value       = azurerm_user_assigned_identity.backup_function.principal_id
}

output "backup_action_group_id" {
  description = "The ID of the action group for backup alerts"
  value       = azurerm_monitor_action_group.backup_alerts.id
}

output "backup_function_app_url" {
  description = "The URL of the backup function app"
  value       = azurerm_linux_function_app.backup_function.default_hostname
} 