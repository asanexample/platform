/**
 * Output variables for the Azure Container Registry Module
 * 
 * These outputs enable integration with other modules and easy access to registry properties
 */

output "id" {
  description = "The ID of the Azure Container Registry."
  value       = azurerm_container_registry.acr.id
}

output "name" {
  description = "The name of the Azure Container Registry."
  value       = azurerm_container_registry.acr.name
}

output "login_server" {
  description = "The URL that can be used to log into the container registry."
  value       = azurerm_container_registry.acr.login_server
}

output "admin_username" {
  description = "The Admin Username for the Container Registry."
  value       = var.admin_enabled ? azurerm_container_registry.acr.admin_username : null
  sensitive   = true
}

output "admin_password" {
  description = "The Admin Password for the Container Registry."
  value       = var.admin_enabled ? azurerm_container_registry.acr.admin_password : null
  sensitive   = true
}

output "identity" {
  description = "The managed identity assigned to the Container Registry."
  value = {
    principal_id = azurerm_container_registry.acr.identity[0].principal_id
    tenant_id    = azurerm_container_registry.acr.identity[0].tenant_id
    type         = azurerm_container_registry.acr.identity[0].type
  }
}

output "resource_group_name" {
  description = "The name of the resource group in which the ACR exists."
  value       = azurerm_container_registry.acr.resource_group_name
}

output "location" {
  description = "The Azure region where the ACR exists."
  value       = azurerm_container_registry.acr.location
}

output "sku" {
  description = "The SKU of the Azure Container Registry."
  value       = azurerm_container_registry.acr.sku
}

output "admin_enabled" {
  description = "Whether admin access is enabled."
  value       = azurerm_container_registry.acr.admin_enabled
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled."
  value       = azurerm_container_registry.acr.public_network_access_enabled
}

output "zone_redundancy_enabled" {
  description = "Whether zone redundancy is enabled."
  value       = azurerm_container_registry.acr.zone_redundancy_enabled
}

output "network_rule_set" {
  description = "The network rule set for the ACR."
  value       = var.sku != "Basic" && var.network_rule_set != null ? var.network_rule_set : null
}

output "geo_replications" {
  description = "The geo-replications of the ACR."
  value       = local.geo_replication_enabled ? var.geo_replication_locations : []
}

output "encryption_enabled" {
  description = "Whether encryption is enabled."
  value       = var.sku == "Premium" && var.encryption_enabled
}

output "acr_pull_role_assignment_id" {
  description = "The ID of the AcrPull role assignment (if AKS integration is enabled)."
  value       = var.aks_integration_enabled && var.aks_principal_id != null ? azurerm_role_assignment.acr_pull[0].id : null
}

output "acr_push_role_assignment_id" {
  description = "The ID of the AcrPush role assignment (if AKS integration and push are enabled)."
  value       = var.aks_integration_enabled && var.enable_aks_acr_push && var.aks_principal_id != null ? azurerm_role_assignment.acr_push[0].id : null
}

output "lock_id" {
  description = "The ID of the resource lock (if enabled)."
  value       = var.lock_resource ? azurerm_management_lock.acr_lock[0].id : null
} 