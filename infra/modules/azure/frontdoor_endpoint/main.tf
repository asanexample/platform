/**
 * # Azure Front Door Endpoint Module
 *
 * This module creates an Azure Front Door endpoint with an origin group.
 * It provides the structure needed for adding origins and routes.
 * Deployment can be controlled using the `create` variable.
 */

# Fetch the existing Front Door profile if profile_id is not provided
data "azurerm_cdn_frontdoor_profile" "profile" {
  count               = var.create && var.profile_id == null ? 1 : 0
  name                = var.profile_name
  resource_group_name = var.profile_resource_group_name
}

locals {
  profile_id = var.profile_id != null ? var.profile_id : (var.create ? data.azurerm_cdn_frontdoor_profile.profile[0].id : null)
}

# Create the Front Door endpoint
resource "azurerm_cdn_frontdoor_endpoint" "this" {
  count                    = var.create ? 1 : 0
  name                     = var.endpoint_name
  cdn_frontdoor_profile_id = local.profile_id
  tags                     = var.tags
}

# Create the origin group
resource "azurerm_cdn_frontdoor_origin_group" "this" {
  count                    = var.create ? 1 : 0
  name                     = var.origin_group_name
  cdn_frontdoor_profile_id = local.profile_id

  # Load balancing configuration
  dynamic "load_balancing" {
    for_each = var.load_balancing_enabled ? [var.load_balancing_settings] : []
    content {
      additional_latency_in_milliseconds = lookup(load_balancing.value, "additional_latency_in_milliseconds", null)
      sample_size                        = lookup(load_balancing.value, "sample_size", null)
      successful_samples_required        = lookup(load_balancing.value, "successful_samples_required", null)
    }
  }

  # Health probe configuration (optional)
  dynamic "health_probe" {
    for_each = var.health_probe_enabled ? [var.health_probe_settings] : []
    content {
      protocol            = lookup(health_probe.value, "protocol", "Http")
      interval_in_seconds = lookup(health_probe.value, "interval_in_seconds", 120)
      path                = lookup(health_probe.value, "path", "/")
      request_type        = lookup(health_probe.value, "request_type", "HEAD")
    }
  }
} 