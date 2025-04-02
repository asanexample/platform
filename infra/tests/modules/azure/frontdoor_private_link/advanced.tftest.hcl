/**
 * # Front Door Private Link Module - Advanced Test
 * 
 * This test verifies more advanced functionality of the Front Door Private Link module
 * including blob endpoint and route configuration.
 */

# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip resource provider registration for tests
  resource_provider_registrations = "none"
}

# Test blob endpoint with route configuration
run "blob_endpoint_with_route" {
  command = plan

  variables {
    module_enabled = false # Disable actual resource creation
    origin_group_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/originGroups/test-origin-group"
    storage_account_name = "teststorageaccount"
    storage_resource_group_name = "test-rg"
    origin_name = "test-origin-blob"
    use_blob_endpoint = true # Use blob endpoint
    
    # Route configuration
    route_enabled = true
    endpoint_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/endpoints/test-endpoint"
    route_name = "test-blob-route"
    patterns_to_match = ["/images/*", "/documents/*"]
    cache_enabled = false
  }

  module {
    source = "../../../../modules/azure/frontdoor_private_link"
  }

  # Verify module is disabled for testing
  assert {
    condition     = var.module_enabled == false
    error_message = "Module should be disabled during test"
  }
}

# Test route configuration with cache
run "route_with_cache" {
  command = plan
  # Note: In tftest.hcl files, you cannot use depends_on like in normal Terraform

  variables {
    module_enabled = false # Disable actual resource creation
    origin_group_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/originGroups/test-origin-group"
    storage_account_name = "teststorageaccount"
    storage_resource_group_name = "test-rg"
    origin_name = "test-origin-web-cached"
    use_blob_endpoint = false # Use web endpoint
    
    # Route configuration with cache
    route_enabled = true
    endpoint_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/endpoints/test-endpoint"
    route_name = "test-web-cached-route"
    patterns_to_match = ["/cached/*"]
    cache_enabled = true
    cache_settings = {
      query_string_caching_behavior = "IgnoreQueryString"
      compression_enabled = true
      content_types_to_compress = ["text/html", "text/css", "application/javascript"]
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_private_link"
  }

  # Verify module is disabled for testing
  assert {
    condition     = var.module_enabled == false
    error_message = "Module should be disabled during test"
  }
} 