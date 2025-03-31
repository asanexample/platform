output "endpoint_id" {
  description = "The ID of the Front Door endpoint"
  value       = var.enabled ? azurerm_cdn_frontdoor_endpoint.this[0].id : null
}

output "endpoint_name" {
  description = "The name of the Front Door endpoint"
  value       = var.enabled ? azurerm_cdn_frontdoor_endpoint.this[0].name : null
}

output "endpoint_host_name" {
  description = "The host name of the Front Door endpoint"
  value       = var.enabled ? azurerm_cdn_frontdoor_endpoint.this[0].host_name : null
}

output "origin_group_id" {
  description = "The ID of the origin group"
  value       = var.enabled ? azurerm_cdn_frontdoor_origin_group.this[0].id : null
}

output "origin_group_name" {
  description = "The name of the origin group"
  value       = var.enabled ? azurerm_cdn_frontdoor_origin_group.this[0].name : null
}

output "enabled" {
  description = "Whether the Front Door endpoint is enabled"
  value       = var.enabled
} 