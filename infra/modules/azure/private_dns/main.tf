/**
 * # Azure Private DNS Zones Module
 *
 * This module creates Azure private DNS zones and links them to virtual networks.
 */

# Create private DNS zones
resource "azurerm_private_dns_zone" "this" {
  for_each            = var.private_dns_zones
  name                = each.value.name
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Link private DNS zones to virtual networks
resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each                  = var.private_dns_zones
  name                      = each.value.virtual_network_link_name
  resource_group_name       = var.resource_group_name
  private_dns_zone_name     = azurerm_private_dns_zone.this[each.key].name
  virtual_network_id        = each.value.vnet_id
  registration_enabled      = each.value.registration_enabled
  tags                      = var.tags
} 