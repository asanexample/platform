/**
 * # Shared Infrastructure Outputs
 *
 * Outputs from a deployment of networking, storage, and key vault resources.
 */

# Resource Group outputs
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = azurerm_resource_group.hosting_rg.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = azurerm_resource_group.hosting_rg.id
}

output "location" {
  description = "Azure region where resources were deployed"
  value       = azurerm_resource_group.hosting_rg.location
}

# Network outputs
output "vnet_id" {
  description = "ID of the created virtual network"
  value       = module.network.vnet_id
}

output "vnet_name" {
  description = "Name of the created virtual network"
  value       = module.network.vnet_name
}

output "subnet_ids" {
  description = "Map of subnet names to IDs"
  value       = module.network.subnet_ids
}

output "nsg_ids" {
  description = "Map of Network Security Group names to IDs"
  value       = module.network.nsg_ids
}

# Storage outputs
output "storage_account_id" {
  description = "ID of the created storage account"
  value       = module.storage_account.id
}

output "storage_account_name" {
  description = "Name of the created storage account"
  value       = module.storage_account.name
}

output "storage_primary_blob_endpoint" {
  description = "Primary blob endpoint for the storage account"
  value       = module.storage_account.primary_blob_endpoint
}

output "storage_containers" {
  description = "Map of created containers with their properties"
  value       = module.storage_account.containers
}

# Key Vault outputs
output "key_vault_id" {
  description = "ID of the created Key Vault"
  value       = var.create_key_vault ? module.key_vault[0].id : null
}

output "key_vault_name" {
  description = "Name of the created Key Vault"
  value       = var.create_key_vault ? module.key_vault[0].name : null
}

output "key_vault_uri" {
  description = "URI of the created Key Vault"
  value       = var.create_key_vault ? module.key_vault[0].uri : null
}

output "key_vault_tenant_id" {
  description = "Tenant ID of the Key Vault"
  value       = var.create_key_vault ? module.key_vault[0].tenant_id : null
}

# AKS Cluster outputs
output "aks_cluster_id" {
  description = "The ID of the AKS cluster if created"
  value       = var.create_aks_cluster ? module.aks_cluster[0].id : null
}

output "aks_cluster_name" {
  description = "The name of the AKS cluster if created"
  value       = var.create_aks_cluster ? module.aks_cluster[0].name : null
}

output "aks_host" {
  description = "The AKS cluster host if AKS was created"
  value       = var.create_aks_cluster ? module.aks_cluster[0].host : null
  sensitive   = true
}

output "aks_kube_config" {
  description = "The kubeconfig for the AKS cluster if AKS was created"
  value       = var.create_aks_cluster ? module.aks_cluster[0].kube_config_raw : null
  sensitive   = true
}

output "aks_oidc_issuer_url" {
  description = "The OIDC issuer URL for the AKS cluster if AKS was created"
  value       = var.create_aks_cluster ? module.aks_cluster[0].oidc_issuer_url : null
}

output "aks_identity_principal_id" {
  description = "The principal ID of the AKS identity if created"
  value       = var.create_aks_cluster ? module.aks_cluster[0].aks_identity_principal_id : null
}

output "aks_karpenter_identity_id" {
  description = "The ID of the Karpenter identity if created"
  value       = var.create_aks_cluster ? module.aks_cluster[0].karpenter_identity.id : null
}

# Naming module outputs (always available)
output "naming" {
  description = "Resource name outputs from the naming module"
  value       = module.naming
} 