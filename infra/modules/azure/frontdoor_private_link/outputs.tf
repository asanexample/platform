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

output "private_link_target_id" {
  description = "The target ID of the private link"
  value       = data.azurerm_storage_account.this.id
}

output "private_link_request_message" {
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