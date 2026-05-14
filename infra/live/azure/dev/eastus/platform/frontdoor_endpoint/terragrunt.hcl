# Terragrunt configuration for Azure Front Door Endpoint in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

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
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Cdn/profiles/mock-fd"
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure/frontdoor_endpoint"
}

inputs = {
  create = true

  profile_id        = dependency.frontdoor_profile.outputs.id
  endpoint_name     = dependency.naming.outputs.frontdoor_endpoint
  origin_group_name = dependency.naming.outputs.frontdoor_origin_group

  load_balancing_enabled = true
  load_balancing_settings = {
    sample_size                        = 4
    successful_samples_required        = 2
    additional_latency_in_milliseconds = 50
  }

  health_probe_enabled = true
  health_probe_settings = {
    protocol            = "Https"
    interval_in_seconds = 30
    path                = "/health"
    request_type        = "GET"
  }

  tags = include.base.locals.tags
}
