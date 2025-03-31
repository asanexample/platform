/**
 * # Azure Front Door Private Link Origin Module
 *
 * This module creates an Azure Front Door origin with private link configuration
 * to securely connect to private resources like storage accounts.
 */

# Get origin group if origin_group_id is not provided
data "azurerm_cdn_frontdoor_origin_group" "this" {
  count               = var.origin_group_id == null ? 1 : 0
  name                = var.origin_group_name
  profile_name        = var.profile_name
  resource_group_name = var.profile_resource_group_name
}

# Get storage account details
data "azurerm_storage_account" "this" {
  name                = var.storage_account_name
  resource_group_name = var.storage_resource_group_name
}

locals {
  origin_group_id = var.origin_group_id != null ? var.origin_group_id : data.azurerm_cdn_frontdoor_origin_group.this[0].id
}

# Create origin with private link
resource "azurerm_cdn_frontdoor_origin" "this" {
  name                          = var.origin_name
  cdn_frontdoor_origin_group_id = local.origin_group_id
  enabled                       = var.enabled

  certificate_name_check_enabled = var.certificate_name_check_enabled
  host_name                      = var.use_blob_endpoint ? data.azurerm_storage_account.this.primary_blob_host : data.azurerm_storage_account.this.primary_web_host
  origin_host_header             = var.use_blob_endpoint ? data.azurerm_storage_account.this.primary_blob_host : data.azurerm_storage_account.this.primary_web_host
  priority                       = var.priority
  weight                         = var.weight

  private_link {
    request_message        = var.private_link_request_message
    target_type            = var.use_blob_endpoint ? "blob" : "web"
    location               = data.azurerm_storage_account.this.location
    private_link_target_id = data.azurerm_storage_account.this.id
  }
}

# Create route if route_enabled is true
resource "azurerm_cdn_frontdoor_route" "this" {
  count                       = var.route_enabled ? 1 : 0
  name                        = var.route_name
  cdn_frontdoor_endpoint_id   = var.endpoint_id
  cdn_frontdoor_origin_ids    = [azurerm_cdn_frontdoor_origin.this.id]
  cdn_frontdoor_origin_group_id = local.origin_group_id
  enabled                     = true

  forwarding_protocol    = var.forwarding_protocol
  https_redirect_enabled = var.https_redirect_enabled
  patterns_to_match      = var.patterns_to_match
  supported_protocols    = var.supported_protocols
  link_to_default_domain = var.link_to_default_domain

  dynamic "cache" {
    for_each = var.cache_enabled ? [var.cache_settings] : []
    content {
      query_string_caching_behavior = lookup(cache.value, "query_string_caching_behavior", "IgnoreQueryString")
      query_strings                 = lookup(cache.value, "query_strings", null)
      compression_enabled           = lookup(cache.value, "compression_enabled", false)
      content_types_to_compress     = lookup(cache.value, "content_types_to_compress", null)
    }
  }
} 