# Resource group
output "resource_group_name" {
  description = "Name of the created resource group"
  value       = module.resource_group.name
}

output "resource_group_id" {
  description = "ID of the created resource group"
  value       = module.resource_group.id
}

output "location" {
  description = "Azure region of the stack"
  value       = module.resource_group.location
}

# Networking — cloud-specific
output "vnet_id" {
  description = "Virtual network ID"
  value       = module.networking.vnet_id
}

output "vnet_name" {
  description = "Virtual network name"
  value       = module.networking.vnet_name
}

output "subnet_ids" {
  description = "Map of subnet names to IDs"
  value       = module.networking.subnet_ids
}

# Networking — cross-cloud interface
output "network_id" {
  description = "Cloud-agnostic network identifier"
  value       = module.networking.network_id
}

output "network_name" {
  description = "Cloud-agnostic network name"
  value       = module.networking.network_name
}

output "kubernetes_subnet_id" {
  description = "Cloud-agnostic Kubernetes node subnet ID"
  value       = module.networking.kubernetes_subnet_id
}

# Key Vault
output "key_vault_id" {
  description = "Key Vault ID (null if key vault disabled)"
  value       = module.key_vault.id
}

output "key_vault_name" {
  description = "Key Vault name (null if key vault disabled)"
  value       = module.key_vault.name
}

output "key_vault_uri" {
  description = "Key Vault URI (null if key vault disabled)"
  value       = module.key_vault.uri
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
