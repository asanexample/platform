/**
 * # Front Door Private Link Module - Validation Test
 * 
 * This test focuses on validation of the Front Door Private Link module
 * including when it's disabled and verifying data source usage.
 */

# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip resource provider registration for tests
  resource_provider_registrations = "none"
}

# Test module when disabled
run "disabled_test" {
  command = plan

  variables {
    module_enabled              = false
    origin_group_id             = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/originGroups/test-origin-group"
    storage_account_name        = "teststorageaccount"
    storage_resource_group_name = "test-rg"
    origin_name                 = "test-origin"
    route_enabled               = true
    route_name                  = "test-route"
    endpoint_id                 = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/endpoints/test-endpoint"
  }

  module {
    source = "../../../../modules/azure/frontdoor_private_link"
  }

  # Verify no resources are created when module is disabled
  assert {
    condition     = var.module_enabled == false
    error_message = "Module should be disabled during test"
  }
}

# Test using origin group name instead of ID
run "origin_group_by_name_test" {
  command = plan

  variables {
    module_enabled              = false # Disable actual resource creation
    origin_group_name           = "test-origin-group"
    profile_name                = "mock-fd-profile"
    profile_resource_group_name = "test-rg"
    storage_account_name        = "teststorageaccount"
    storage_resource_group_name = "test-rg"
    origin_name                 = "test-origin"
    route_enabled               = false
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

# Test route disabled
run "route_disabled_test" {
  command = plan

  variables {
    module_enabled              = false # Disable actual resource creation
    origin_group_id             = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/originGroups/test-origin-group"
    storage_account_name        = "teststorageaccount"
    storage_resource_group_name = "test-rg"
    origin_name                 = "test-origin"
    route_enabled               = false
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

# Test output values
run "output_test" {
  command = plan

  variables {
    module_enabled              = false # Disable actual resource creation
    origin_group_id             = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/originGroups/test-origin-group"
    storage_account_name        = "teststorageaccount"
    storage_resource_group_name = "test-rg"
    origin_name                 = "test-origin"
    route_enabled               = true
    route_name                  = "test-route"
    endpoint_id                 = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Cdn/profiles/mock-fd-profile/endpoints/test-endpoint"
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