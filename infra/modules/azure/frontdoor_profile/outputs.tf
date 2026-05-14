output "id" {
  description = "The ID of the Front Door profile"
  value       = var.create ? azurerm_cdn_frontdoor_profile.this[0].id : null
}

output "name" {
  description = "The name of the Front Door profile"
  value       = var.create ? azurerm_cdn_frontdoor_profile.this[0].name : null
}

output "resource_group_name" {
  description = "The name of the resource group where the Front Door profile exists"
  value       = var.create ? azurerm_cdn_frontdoor_profile.this[0].resource_group_name : null
}

output "sku_name" {
  description = "The SKU name of the Front Door profile"
  value       = var.create ? azurerm_cdn_frontdoor_profile.this[0].sku_name : null
}

output "create" {
  description = "Whether the Front Door profile is created"
  value       = var.create
} 