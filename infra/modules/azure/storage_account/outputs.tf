output "id" {
  description = "ID of the created storage account"
  value       = azurerm_storage_account.this.id
}

output "name" {
  description = "Name of the created storage account"
  value       = azurerm_storage_account.this.name
}

output "primary_access_key" {
  description = "Primary access key for the storage account"
  value       = azurerm_storage_account.this.primary_access_key
  sensitive   = true
}

output "primary_connection_string" {
  description = "Primary connection string for the storage account"
  value       = azurerm_storage_account.this.primary_connection_string
  sensitive   = true
}

output "secondary_access_key" {
  description = "Secondary access key for the storage account"
  value       = azurerm_storage_account.this.secondary_access_key
  sensitive   = true
}

output "secondary_connection_string" {
  description = "Secondary connection string for the storage account"
  value       = azurerm_storage_account.this.secondary_connection_string
  sensitive   = true
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = azurerm_storage_account.this.primary_blob_endpoint
}

output "containers" {
  description = "Map of created containers with their properties"
  value       = azurerm_storage_container.containers
}

output "private_endpoint_ids" {
  description = "List of private endpoint IDs if created"
  value       = azurerm_private_endpoint.storage[*].id
} 