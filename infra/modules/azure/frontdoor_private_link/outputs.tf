output "origin_id" {
  description = "The ID of the Front Door origin"
  value       = var.module_enabled ? azurerm_cdn_frontdoor_origin.this[0].id : null
}

output "origin_name" {
  description = "The name of the origin"
  value       = var.module_enabled ? azurerm_cdn_frontdoor_origin.this[0].name : null
}

output "origin_host_name" {
  description = "The host name of the origin"
  value       = var.module_enabled ? azurerm_cdn_frontdoor_origin.this[0].host_name : null
}

output "private_link_target_id" {
  description = "The target ID of the private link"
  value       = var.module_enabled ? var.storage_account_id : null
}

output "private_link_request_message" {
  description = "The approval message used for the private link"
  value       = var.private_link_request_message
}

output "route_id" {
  description = "The ID of the route, if created"
  value       = var.module_enabled && var.route_enabled ? azurerm_cdn_frontdoor_route.this[0].id : null
}

output "route_name" {
  description = "The name of the route, if created"
  value       = var.module_enabled && var.route_enabled ? azurerm_cdn_frontdoor_route.this[0].name : null
}

output "module_enabled" {
  description = "Whether the Front Door Private Link module is enabled"
  value       = var.module_enabled
} 