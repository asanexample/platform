output "id" {
  description = "ID of the created storage account"
  value       = var.create ? azurerm_storage_account.this[0].id : null
}

output "name" {
  description = "Name of the created storage account"
  value       = var.create ? azurerm_storage_account.this[0].name : null
}

output "primary_access_key" {
  description = "Primary access key for the storage account. DEPRECATED: Use Entra ID authentication instead of access keys."
  value       = var.create ? azurerm_storage_account.this[0].primary_access_key : null
  sensitive   = true
}

output "primary_connection_string" {
  description = "Primary connection string for the storage account. DEPRECATED: Use Entra ID authentication instead of connection strings."
  value       = var.create ? azurerm_storage_account.this[0].primary_connection_string : null
  sensitive   = true
}

output "secondary_access_key" {
  description = "Secondary access key for the storage account. DEPRECATED: Use Entra ID authentication instead of access keys."
  value       = var.create ? azurerm_storage_account.this[0].secondary_access_key : null
  sensitive   = true
}

output "secondary_connection_string" {
  description = "Secondary connection string for the storage account. DEPRECATED: Use Entra ID authentication instead of connection strings."
  value       = var.create ? azurerm_storage_account.this[0].secondary_connection_string : null
  sensitive   = true
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = var.create ? azurerm_storage_account.this[0].primary_blob_endpoint : null
}

output "containers" {
  description = "Map of created containers with their properties"
  value       = var.create ? azurerm_storage_container.containers : {}
}

output "private_endpoint_ids" {
  description = "List of private endpoint IDs if created"
  value       = var.create ? azurerm_private_endpoint.storage[*].id : []
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
