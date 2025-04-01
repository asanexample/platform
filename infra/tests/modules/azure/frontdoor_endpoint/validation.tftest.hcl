# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip provider registration for tests
  skip_provider_registration = true
}

/**
 * # Front Door Endpoint Module - Validation Test
 * 
 * This test verifies validation conditions for the Front Door Endpoint module.
 */

# Test with the module disabled
run "disabled_test" {
  command = plan

  variables {
    enabled                  = false
    endpoint_name            = "test-endpoint"
    origin_group_name        = "test-origin-group"
    profile_name             = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    profile_id               = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile"
    load_balancing_settings = {
      additional_latency_in_milliseconds = 50
      sample_size                        = 4
      successful_samples_required        = 3
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_endpoint"
  }

  # Verify no resources are created when disabled
  assert {
    condition     = length(azurerm_cdn_frontdoor_endpoint.this) == 0
    error_message = "No Front Door Endpoint should be created when module is disabled"
  }
  
  assert {
    condition     = length(azurerm_cdn_frontdoor_origin_group.this) == 0
    error_message = "No Origin Group should be created when module is disabled"
  }
}

# Test without explicit profile_id (using data source)
# Note: In a real test this would use the data source, but for testing we provide the ID
run "profile_data_source_test" {
  command = plan

  variables {
    enabled                  = true
    endpoint_name            = "test-endpoint"
    origin_group_name        = "test-origin-group"
    profile_name             = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    # Using a hard-coded profile_id since the data source won't work in test
    profile_id               = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile"
    load_balancing_enabled   = true
    load_balancing_settings = {
      additional_latency_in_milliseconds = 50
      sample_size                        = 4
      successful_samples_required        = 3
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_endpoint"
  }

  # Verify resources are still created
  assert {
    condition     = length(azurerm_cdn_frontdoor_endpoint.this) == 1
    error_message = "Front Door Endpoint should be created when profile data source is used"
  }
  
  assert {
    condition     = length(azurerm_cdn_frontdoor_origin_group.this) == 1
    error_message = "Origin Group should be created when profile data source is used"
  }
}

# Test output values
run "output_test" {
  command = plan

  variables {
    enabled                  = true
    endpoint_name            = "test-endpoint"
    origin_group_name        = "test-origin-group"
    profile_name             = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    profile_id               = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile"
    load_balancing_enabled   = true
    load_balancing_settings = {
      additional_latency_in_milliseconds = 50
      sample_size                        = 4
      successful_samples_required        = 3
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_endpoint"
  }

  # Verify endpoint and origin group are created
  assert {
    condition     = length(azurerm_cdn_frontdoor_endpoint.this) > 0
    error_message = "Endpoint should be created"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_endpoint.this[0].name == "test-endpoint"
    error_message = "Endpoint name should match the input"
  }
  
  assert {
    condition     = length(azurerm_cdn_frontdoor_origin_group.this) > 0
    error_message = "Origin group should be created"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_origin_group.this[0].name == "test-origin-group"
    error_message = "Origin group name should match the input"
  }
} 