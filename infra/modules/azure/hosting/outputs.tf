/**
 * # Hosting Module Outputs
 * 
 * Outputs from the hosting module, including both networking and storage resources.
 */

# Resource Group
output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.hosting_rg.name
}

output "resource_group_id" {
  description = "ID of the resource group"
  value       = azurerm_resource_group.hosting_rg.id
}

output "location" {
  description = "Location of the resource group"
  value       = azurerm_resource_group.hosting_rg.location
}

# Network Outputs
output "vnet_id" {
  description = "ID of the virtual network"
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "Name of the virtual network"
  value       = module.network.vnet_name
}

output "subnet_ids" {
  description = "Map of subnet names to IDs"
  value       = module.network.subnet_ids
}

# Storage Outputs
output "storage_account_id" {
  description = "ID of the storage account"
  value       = module.storage_account.id
}

output "storage_account_name" {
  description = "Name of the storage account"
  value       = module.storage_account.name
}

output "primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = module.storage_account.primary_blob_endpoint
}

output "containers" {
  description = "Map of created containers with their properties"
  value       = module.storage_account.containers
}

# Naming module outputs (always available)
output "naming" {
  description = "Resource name outputs from the naming module"
  value       = module.naming
} 