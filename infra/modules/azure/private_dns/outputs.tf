output "private_dns_zone_ids" {
  description = "Map of private DNS zone names to their IDs"
  value       = { for k, v in azurerm_private_dns_zone.this : k => v.id }
} 