# Terragrunt configuration for Azure Front Door Private Link in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

# Module-specific locals
locals {
  default_id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Cdn/profiles/mock-fd"
  mock_origin_group_id = "${local.default_id}/originGroups/mock-og"
  mock_endpoint_id     = "${local.default_id}/afdEndpoints/mock-endpoint"
}

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
    create            = true
  }
}

dependency "storage" {
  config_path = "../storage"

  mock_outputs = {
    id                    = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mocksa"
    name                  = "mocksa"
    primary_blob_endpoint = "https://mocksa.blob.core.windows.net/"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name     = "mock-rg"
    location = "eastus"
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure/frontdoor_private_link"
}

inputs = {
  create          = lookup(dependency.frontdoor_endpoint.outputs, "create", true)
  origin_group_id = try(dependency.frontdoor_endpoint.outputs.origin_group_id, local.mock_origin_group_id)

  storage_account_name        = dependency.storage.outputs.name
  storage_resource_group_name = dependency.resource_group.outputs.name
  storage_account_id          = dependency.storage.outputs.id
  storage_primary_blob_host   = trimsuffix(trimprefix(dependency.storage.outputs.primary_blob_endpoint, "https://"), "/")
  storage_primary_web_host    = trimsuffix(trimprefix(dependency.storage.outputs.primary_blob_endpoint, "https://"), "/")
  storage_location            = dependency.resource_group.outputs.location

  origin_name                  = dependency.naming.outputs.frontdoor_origin
  private_link_request_message = "Request access for Front Door Origin from ${include.base.locals.env} environment"

  route_enabled       = true
  endpoint_id         = try(dependency.frontdoor_endpoint.outputs.endpoint_id, local.mock_endpoint_id)
  route_name          = dependency.naming.outputs.frontdoor_route
  patterns_to_match   = ["/*"]
  forwarding_protocol = "HttpsOnly"

  cache_enabled = true
  cache_settings = {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress = [
      "application/json",
      "text/html",
      "text/css",
      "text/javascript",
      "application/javascript"
    ]
  }
}
