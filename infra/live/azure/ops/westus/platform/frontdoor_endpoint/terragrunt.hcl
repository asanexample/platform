# Terragrunt configuration for Azure Front Door Endpoint in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root configuration (root.hcl)
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    frontdoor_endpoint     = "mock-fd-endpoint"
    frontdoor_origin_group = "mock-fd-og"
  }
}

dependency "frontdoor_profile" {
  config_path = "../frontdoor_profile"
  mock_outputs = {
    id     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Cdn/profiles/mock-fd"
    create = false
  }
}

# Define terraform source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/frontdoor_endpoint"
}

# Specify inputs specific to this module
inputs = {
  # Conditional deployment based on profile
  create = dependency.frontdoor_profile.outputs.create

  # Front Door profile reference - conditionally use id only when enabled
  profile_id = dependency.frontdoor_profile.outputs.create ? dependency.frontdoor_profile.outputs.id : null

  # Endpoint and origin group names
  endpoint_name     = dependency.naming.outputs.frontdoor_endpoint
  origin_group_name = dependency.naming.outputs.frontdoor_origin_group

  # Load balancing configuration - more robust settings for production
  load_balancing_enabled = true
  load_balancing_settings = {
    sample_size                        = 8
    successful_samples_required        = 5
    additional_latency_in_milliseconds = 25
  }

  # Health probe configuration - more frequent checks for production
  health_probe_enabled = true
  health_probe_settings = {
    protocol            = "Https"
    interval_in_seconds = 15
    path                = "/health"
    request_type        = "GET"
  }

  # Tags
  tags = include.base.locals.tags
}
