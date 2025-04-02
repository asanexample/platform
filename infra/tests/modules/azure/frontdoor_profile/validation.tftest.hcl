# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip resource provider registration for tests
  resource_provider_registrations = "none"
}

/**
 * # Front Door Profile Module - Validation Test
 * 
 * This test verifies validation conditions and edge cases for the Front Door Profile module.
 */

# Test with minimum response timeout
run "min_response_timeout_test" {
  command = plan

  variables {
    name                     = "test-fd-profile"
    resource_group_name      = "test-rg"
    enabled                  = true
    sku_name                 = "Standard_AzureFrontDoor"
    response_timeout_seconds = 16 # Minimum allowed value
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify minimum response timeout
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].response_timeout_seconds == 16
    error_message = "Front Door Profile should accept minimum response timeout of 16 seconds"
  }
}

# Test with maximum response timeout
run "max_response_timeout_test" {
  command = plan

  variables {
    name                     = "test-fd-profile"
    resource_group_name      = "test-rg"
    enabled                  = true
    sku_name                 = "Standard_AzureFrontDoor"
    response_timeout_seconds = 240 # Maximum allowed value
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify maximum response timeout
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].response_timeout_seconds == 240
    error_message = "Front Door Profile should accept maximum response timeout of 240 seconds"
  }
}

# Test with Standard SKU
run "standard_sku_test" {
  command = plan

  variables {
    name                = "test-fd-profile"
    resource_group_name = "test-rg"
    enabled             = true
    sku_name            = "Standard_AzureFrontDoor"
    response_timeout_seconds = 120
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify Standard SKU
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].sku_name == "Standard_AzureFrontDoor"
    error_message = "Front Door Profile should accept Standard_AzureFrontDoor SKU"
  }
}

# Test with Premium SKU
run "premium_sku_test" {
  command = plan

  variables {
    name                = "test-fd-profile"
    resource_group_name = "test-rg"
    enabled             = true
    sku_name            = "Premium_AzureFrontDoor"
    response_timeout_seconds = 120
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify Premium SKU
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].sku_name == "Premium_AzureFrontDoor"
    error_message = "Front Door Profile should accept Premium_AzureFrontDoor SKU"
  }
}

# Test with long name
run "long_name_test" {
  command = plan

  variables {
    name                = "test-frontdoor-profile-with-a-longer-name-that-is-valid-within-Azure-constraints"
    resource_group_name = "test-rg"
    enabled             = true
    sku_name            = "Standard_AzureFrontDoor"
    response_timeout_seconds = 120
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify long name
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].name == "test-frontdoor-profile-with-a-longer-name-that-is-valid-within-Azure-constraints"
    error_message = "Front Door Profile should accept longer valid names"
  }
} 