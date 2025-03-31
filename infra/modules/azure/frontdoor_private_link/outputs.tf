output "origin_id" {
  description = "The ID of the Front Door origin"
  value       = azurerm_cdn_frontdoor_origin.this.id
}

output "origin_name" {
  description = "The name of the origin"
  value       = azurerm_cdn_frontdoor_origin.this.name
}

output "origin_host_name" {
  description = "The host name of the origin"
  value       = azurerm_cdn_frontdoor_origin.this.host_name
}

output "private_link_id" {
  description = "The ID of the private link"
  value       = azurerm_cdn_frontdoor_origin.this.private_link[0].id
}

output "private_link_status" {
  description = "The status of the private link"
  value       = azurerm_cdn_frontdoor_origin.this.private_link[0].status
}

output "private_link_approval_message" {
  description = "The approval message used for the private link"
  value       = var.private_link_request_message
}

output "route_id" {
  description = "The ID of the route, if created"
  value       = var.route_enabled ? azurerm_cdn_frontdoor_route.this[0].id : null
}

output "route_name" {
  description = "The name of the route, if created"
  value       = var.route_enabled ? azurerm_cdn_frontdoor_route.this[0].name : null
} 