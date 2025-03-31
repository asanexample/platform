# Terragrunt configuration for Azure Front Door Endpoint in westus region

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Merge all variables for convenience
  all_vars = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
    local.common_vars.locals
  )
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    frontdoor_endpoint    = "mock-fd-endpoint"
    frontdoor_origin_group = "mock-fd-og"
  }
}

dependency "frontdoor_profile" {
  config_path = "../frontdoor_profile"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Cdn/profiles/mock-fd"
    enabled = false
  }
}

# Define terraform source
terraform {
  source = "${get_path_to_repo_root()}/infra/modules/azure/frontdoor_endpoint"
}

# Specify inputs specific to this module
inputs = {
  # Conditional deployment based on profile
  enabled = dependency.frontdoor_profile.outputs.enabled
  
  # Front Door profile reference - conditionally use id only when enabled
  profile_id = dependency.frontdoor_profile.outputs.enabled ? dependency.frontdoor_profile.outputs.id : null
  
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
  tags = local.tags
} 