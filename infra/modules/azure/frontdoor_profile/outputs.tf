output "id" {
  description = "The ID of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.this.id
}

output "name" {
  description = "The name of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.this.name
}

output "resource_group_name" {
  description = "The name of the resource group where the Front Door profile exists"
  value       = azurerm_cdn_frontdoor_profile.this.resource_group_name
}

output "sku_name" {
  description = "The SKU name of the Front Door profile"
  value       = azurerm_cdn_frontdoor_profile.this.sku_name
} 