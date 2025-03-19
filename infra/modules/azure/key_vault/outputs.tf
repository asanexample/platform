output "id" {
  description = "ID of the created Key Vault"
  value       = azurerm_key_vault.key_vault.id
}

output "name" {
  description = "Name of the created Key Vault"
  value       = azurerm_key_vault.key_vault.name
}

output "uri" {
  description = "URI of the created Key Vault"
  value       = azurerm_key_vault.key_vault.vault_uri
}

output "tenant_id" {
  description = "Tenant ID of the Key Vault"
  value       = azurerm_key_vault.key_vault.tenant_id
}

output "public_network_access_enabled" {
  description = "Whether public network access is enabled for the Key Vault"
  value       = azurerm_key_vault.key_vault.public_network_access_enabled
}

output "access_policy_ids" {
  description = "IDs of the created access policies"
  value       = [for policy in azurerm_key_vault_access_policy.policies : policy.id]
}

output "private_endpoint_ids" {
  description = "IDs of the created private endpoints"
  value       = azurerm_private_endpoint.key_vault[*].id
} 