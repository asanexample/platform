/**
 * # Azure Front Door Profile Module
 *
 * This module creates an Azure Front Door profile, which is the parent resource
 * for Front Door endpoints, origin groups, and other Front Door components.
 * The deployment can be controlled using the `create` variable.
 */

resource "azurerm_cdn_frontdoor_profile" "this" {
  count = var.create ? 1 : 0
  # Name will be provided by Terragrunt using the naming module if null
  name                     = var.name
  resource_group_name      = var.resource_group_name
  sku_name                 = var.sku_name
  response_timeout_seconds = var.response_timeout_seconds
  tags                     = var.tags
} 