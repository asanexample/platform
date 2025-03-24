/**
 * Output variables for the Azure Container Registry Module
 * 
 * These outputs enable integration with other modules and easy access to registry properties
 */

output "id" {
  description = "The ID of the Azure Container Registry."
  value       = var.create_registry ? azurerm_container_registry.acr[0].id : null
}

output "name" {
  description = "The name of the Azure Container Registry."
  value       = var.create_registry ? azurerm_container_registry.acr[0].name : null
}

output "login_server" {
  description = "The URL that can be used to log into the container registry."
  value       = var.create_registry ? azurerm_container_registry.acr[0].login_server : null
}

output "admin_username" {
  description = "The Admin Username for the Container Registry."
  value       = var.create_registry && var.admin_enabled ? azurerm_container_registry.acr[0].admin_username : null
  sensitive   = true
}

output "admin_password" {
  description = "The Admin Password for the Container Registry."
  value       = var.create_registry && var.admin_enabled ? azurerm_container_registry.acr[0].admin_password : null
  sensitive   = true
}

output "identity" {
  description = "The managed identity assigned to the Container Registry."
  value       = var.create_registry ? {
    principal_id = azurerm_container_registry.acr[0].identity[0].principal_id
    tenant_id    = azurerm_container_registry.acr[0].identity[0].tenant_id
    type         = azurerm_container_registry.acr[0].identity[0].type
  } : null
}

output "resource_group_name" {
  description = "The name of the resource group in which the ACR exists."
  value       = var.create_registry ? azurerm_container_registry.acr[0].resource_group_name : null
}

output "location" {
  description = "The Azure region where the ACR exists."
  value       = var.create_registry ? azurerm_container_registry.acr[0].location : null
}

output "sku" {
  description = "The SKU of the Azure Container Registry."
  value       = var.create_registry ? azurerm_container_registry.acr[0].sku : null
}

output "admin_enabled" {
  description = "Whether admin access is enabled."
  value       = var.create_registry ? azurerm_container_registry.acr[0].admin_enabled : null
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled."
  value       = var.create_registry ? azurerm_container_registry.acr[0].public_network_access_enabled : null
}

output "zone_redundancy_enabled" {
  description = "Whether zone redundancy is enabled."
  value       = var.create_registry ? azurerm_container_registry.acr[0].zone_redundancy_enabled : null
}

output "network_rule_set" {
  description = "The network rule set for the ACR."
  value       = var.create_registry && var.sku != "Basic" && var.network_rule_set != null ? var.network_rule_set : null
}

output "geo_replications" {
  description = "The geo-replications of the ACR."
  value       = var.create_registry && local.geo_replication_enabled ? var.geo_replication_locations : []
}

output "encryption_enabled" {
  description = "Whether encryption is enabled."
  value       = var.create_registry ? (var.sku == "Premium" && var.encryption_enabled) : null
}

output "acr_pull_role_assignment_id" {
  description = "The ID of the AcrPull role assignment (if AKS integration is enabled)."
  value       = var.create_registry && var.aks_integration_enabled && var.aks_principal_id != null ? azurerm_role_assignment.acr_pull[0].id : null
}

output "acr_push_role_assignment_id" {
  description = "The ID of the AcrPush role assignment (if AKS integration and push are enabled)."
  value       = var.create_registry && var.aks_integration_enabled && var.enable_aks_acr_push && var.aks_principal_id != null ? azurerm_role_assignment.acr_push[0].id : null
}

output "lock_id" {
  description = "The ID of the resource lock (if enabled)."
  value       = var.create_registry && var.lock_resource ? azurerm_management_lock.acr_lock[0].id : null
}

output "created" {
  description = "Indicates whether the ACR was created by this module."
  value       = var.create_registry
} 