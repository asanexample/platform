output "endpoint_id" {
  description = "The ID of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.this.id
}

output "endpoint_name" {
  description = "The name of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.this.name
}

output "endpoint_host_name" {
  description = "The host name of the Front Door endpoint"
  value       = azurerm_cdn_frontdoor_endpoint.this.host_name
}

output "origin_group_id" {
  description = "The ID of the origin group"
  value       = azurerm_cdn_frontdoor_origin_group.this.id
}

output "origin_group_name" {
  description = "The name of the origin group"
  value       = azurerm_cdn_frontdoor_origin_group.this.name
} 