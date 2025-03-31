/**
 * # Azure Front Door Profile Module
 *
 * This module creates an Azure Front Door profile, which is the parent resource
 * for Front Door endpoints, origin groups, and other Front Door components.
 * The deployment can be controlled using the `enabled` variable.
 */

resource "azurerm_cdn_frontdoor_profile" "this" {
  count                    = var.enabled ? 1 : 0
  name                     = var.name
  resource_group_name      = var.resource_group_name
  sku_name                 = var.sku_name
  response_timeout_seconds = var.response_timeout_seconds
  tags                     = var.tags
} 