# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip resource provider registration for tests
  resource_provider_registrations = "none"
}

/**
 * # Front Door Profile Module - Advanced Test
 * 
 * This test verifies advanced functionality of the Front Door Profile module
 * with custom settings and tags.
 */

# Test Front Door Profile with custom settings
run "custom_settings_test" {
  command = plan

  variables {
    name                     = "test-fd-profile"
    resource_group_name      = "test-rg"
    enabled                  = true
    sku_name                 = "Premium_AzureFrontDoor"
    response_timeout_seconds = 60
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify custom SKU is set correctly
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].sku_name == "Premium_AzureFrontDoor"
    error_message = "Front Door Profile should use the specified Premium SKU"
  }
  
  # Verify custom response timeout
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].response_timeout_seconds == 60
    error_message = "Front Door Profile should have 60 seconds response timeout as specified"
  }
}

# Test Front Door Profile with custom tags
run "custom_tags_test" {
  command = plan

  variables {
    name                = "test-fd-profile"
    resource_group_name = "test-rg"
    enabled             = true
    sku_name            = "Standard_AzureFrontDoor"
    response_timeout_seconds = 120
    tags = {
      Environment     = "Test"
      CostCenter      = "IT"
      ApplicationName = "FrontDoor"
      Component       = "CDN"
    }
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify Front Door Profile has custom tags
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].tags.Environment == "Test"
    error_message = "Front Door Profile should have the Environment tag set"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].tags.CostCenter == "IT"
    error_message = "Front Door Profile should have the CostCenter tag set"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].tags.ApplicationName == "FrontDoor"
    error_message = "Front Door Profile should have the ApplicationName tag set"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].tags.Component == "CDN"
    error_message = "Front Door Profile should have the Component tag set"
  }
}

# Test Front Door Profile disabled
run "disabled_profile_test" {
  command = plan

  variables {
    name                = "test-fd-profile"
    resource_group_name = "test-rg"
    enabled             = false
    sku_name            = "Standard_AzureFrontDoor"
    response_timeout_seconds = 120
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify Front Door Profile is not created when disabled
  assert {
    condition     = length(azurerm_cdn_frontdoor_profile.this) == 0
    error_message = "Front Door Profile should not be created when disabled"
  }
}

# Test output values
run "output_values_test" {
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

  # Verify values are set correctly when enabled
  assert {
    condition     = length(azurerm_cdn_frontdoor_profile.this) > 0
    error_message = "Front Door Profile should be created when enabled"
  }
  
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].name == "test-fd-profile"
    error_message = "Front Door Profile name should match the input"
  }
} 