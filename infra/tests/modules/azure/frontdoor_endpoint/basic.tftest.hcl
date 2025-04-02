# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip resource provider registration for tests
  resource_provider_registrations = "none"
}

/**
 * # Front Door Endpoint Module - Basic Test
 * 
 * This test verifies the basic functionality of the Front Door Endpoint module
 * with minimal configuration.
 */

# Use a mock for the Front Door profile data source
run "create_mock_profile" {
  # This is just to create a mock that we'll use in the actual test
  command = apply

  module {
    source = "./mocks/mock_profile"
  }
}

# Test basic Front Door Endpoint creation
run "basic_frontdoor_endpoint" {
  command = plan
  variables {
    enabled                  = true
    endpoint_name            = "test-endpoint"
    origin_group_name        = "test-origin-group"
    profile_name             = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    profile_id               = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile" 
    tags = {
      environment = "test"
    }
    load_balancing_enabled = true
    load_balancing_settings = {
      additional_latency_in_milliseconds = 50
      sample_size                        = 4
      successful_samples_required        = 3
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_endpoint"
  }

  # Verify Front Door Endpoint is created with correct name
  assert {
    condition     = azurerm_cdn_frontdoor_endpoint.this[0].name == "test-endpoint"
    error_message = "Front Door Endpoint should be created with the specified name"
  }

  # Verify origin group is created
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].name == "test-origin-group"
    error_message = "Origin group should be created with the specified name"
  }

  # Verify profile ID is set correctly
  assert {
    condition     = azurerm_cdn_frontdoor_endpoint.this[0].cdn_frontdoor_profile_id == var.profile_id
    error_message = "Front Door Endpoint should use the specified profile ID"
  }
} 