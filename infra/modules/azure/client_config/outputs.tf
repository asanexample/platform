output "client_id" {
  description = "The client ID (application ID) of the current Azure client"
  value       = data.azurerm_client_config.current.client_id
}

output "tenant_id" {
  description = "The tenant ID of the current Azure client"
  value       = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  description = "The subscription ID of the current Azure client"
  value       = data.azurerm_client_config.current.subscription_id
}

output "object_id" {
  description = "The object ID of the current Azure client (user or service principal)"
  value       = data.azurerm_client_config.current.object_id
} 