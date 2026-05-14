output "id" {
  description = "ID of the created Key Vault"
  value       = var.create ? azurerm_key_vault.key_vault[0].id : null
}

output "name" {
  description = "Name of the created Key Vault"
  value       = var.create ? azurerm_key_vault.key_vault[0].name : null
}

output "uri" {
  description = "URI of the created Key Vault"
  value       = var.create ? azurerm_key_vault.key_vault[0].vault_uri : null
}

output "tenant_id" {
  description = "Tenant ID of the Key Vault"
  value       = var.create ? azurerm_key_vault.key_vault[0].tenant_id : null
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled for the Key Vault"
  value       = var.create ? azurerm_key_vault.key_vault[0].public_network_access_enabled : null
}

output "access_policy_ids" {
  description = "IDs of the created access policies"
  value       = var.create ? [for policy in azurerm_key_vault_access_policy.policies : policy.id] : []
}

output "private_endpoint_ids" {
  description = "IDs of the created private endpoints"
  value       = var.create ? azurerm_private_endpoint.key_vault[*].id : []
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
