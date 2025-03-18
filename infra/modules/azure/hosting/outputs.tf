/**
 * # Shared Infrastructure Outputs
 * 
 * Outputs for both networking and storage resources.
 */

# Resource group outputs
output "resource_group_name" {
  description = "The name of the resource group"
  value       = azurerm_resource_group.hosting_rg.name
}

output "resource_group_id" {
  description = "The ID of the resource group"
  value       = azurerm_resource_group.hosting_rg.id
}

# Network outputs
output "vnet_id" {
  description = "The ID of the virtual network"
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "The name of the virtual network"
  value       = module.network.vnet_name
}

output "subnet_ids" {
  description = "Map of subnet names to IDs"
  value       = module.network.subnet_ids
}

output "nsg_ids" {
  description = "Map of subnet names to network security group IDs"
  value       = module.network.nsg_ids
}

# Storage outputs
output "storage_account_name" {
  description = "The name of the storage account"
  value       = module.storage_account.name
}

output "storage_account_id" {
  description = "The ID of the storage account"
  value       = module.storage_account.id
}

output "storage_primary_access_key" {
  description = "The primary access key for the storage account"
  value       = module.storage_account.primary_access_key
  sensitive   = true
}

output "storage_primary_connection_string" {
  description = "The primary connection string for the storage account"
  value       = module.storage_account.primary_connection_string
  sensitive   = true
}

output "storage_primary_blob_endpoint" {
  description = "The primary blob endpoint URL"
  value       = module.storage_account.primary_blob_endpoint
}

output "storage_containers" {
  description = "Map of created containers with their properties"
  value       = module.storage_account.containers
} 