/**
 * # Azure Front Door Profile Module
 *
 * This module creates an Azure Front Door profile, which is the parent resource
 * for Front Door endpoints, origin groups, and other Front Door components.
 */

resource "azurerm_cdn_frontdoor_profile" "this" {
  name                     = var.name
  resource_group_name      = var.resource_group_name
  sku_name                 = var.sku_name
  response_timeout_seconds = var.response_timeout_seconds
  tags                     = var.tags
} 