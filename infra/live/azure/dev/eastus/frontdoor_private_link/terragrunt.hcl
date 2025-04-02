# Terragrunt configuration for Azure Front Door Private Link in eastus region

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
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
  
  # Default values to use when module is disabled
  default_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Cdn/profiles/mock-fd"
  mock_origin_group_id = "${local.default_id}/originGroups/mock-og"
  mock_endpoint_id = "${local.default_id}/afdEndpoints/mock-endpoint"
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    frontdoor_origin = "mock-fd-origin"
    frontdoor_route  = "mock-fd-route"
  }
}

dependency "frontdoor_endpoint" {
  config_path = "../frontdoor_endpoint"
  mock_outputs = {
    endpoint_id       = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Cdn/profiles/mock-fd/afdEndpoints/mock-endpoint"
    origin_group_id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Cdn/profiles/mock-fd/originGroups/mock-og"
    endpoint_name     = "mock-endpoint"
    origin_group_name = "mock-origin-group"
    enabled           = true
  }
}

dependency "storage" {
  config_path = "../storage"
  mock_outputs = {
    name           = "mockstorage"
    resource_group = "mock-rg"
  }
}

# Define terraform source
terraform {
  source = "${get_path_to_repo_root()}/infra/modules/azure/frontdoor_private_link"
}

# Specify inputs specific to this module
inputs = {
  # Control deployment
  module_enabled = lookup(dependency.frontdoor_endpoint.outputs, "enabled", true)
  
  # Origin group reference
  origin_group_id = try(dependency.frontdoor_endpoint.outputs.origin_group_id, local.mock_origin_group_id)
  
  # Storage account to connect to
  storage_account_name        = dependency.storage.outputs.name
  storage_resource_group_name = "vip-dev-rg-eus"
  use_blob_endpoint           = true
  
  # Origin configuration
  origin_name                  = dependency.naming.outputs.frontdoor_origin
  private_link_request_message = "Request access for Front Door Origin from ${local.env} environment"
  
  # Route configuration
  route_enabled       = true
  endpoint_id         = try(dependency.frontdoor_endpoint.outputs.endpoint_id, local.mock_endpoint_id)
  route_name          = dependency.naming.outputs.frontdoor_route
  patterns_to_match   = ["/*"]
  forwarding_protocol = "HttpsOnly"
  
  # Caching configuration
  cache_enabled = true
  cache_settings = {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = [
      "application/json",
      "text/html",
      "text/css",
      "text/javascript",
      "application/javascript"
    ]
  }
} 