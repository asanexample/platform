# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  # Skip resource provider registration for tests
  resource_provider_registrations = "none"
}

/**
 * # Front Door Profile Module - Basic Test
 * 
 * This test verifies the basic functionality of the Front Door Profile module
 * with minimal configuration.
 */

# Test basic Front Door Profile creation
run "basic_frontdoor_profile" {
  command = plan

  variables {
    name                     = "test-fd-profile"
    resource_group_name      = "test-rg"
    enabled                  = true
    sku_name                 = "Standard_AzureFrontDoor"
    response_timeout_seconds = 120
  }

  module {
    source = "../../../../modules/azure/frontdoor_profile"
  }

  # Verify Front Door Profile is created with the correct name
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].name == "test-fd-profile"
    error_message = "Front Door Profile should be created with the specified name"
  }

  # Verify resource group is set correctly
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].resource_group_name == "test-rg"
    error_message = "Front Door Profile should be in the correct resource group"
  }

  # Verify default SKU is Standard_AzureFrontDoor
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].sku_name == "Standard_AzureFrontDoor"
    error_message = "Front Door Profile should use Standard_AzureFrontDoor SKU by default"
  }

  # Verify default response timeout
  assert {
    condition     = azurerm_cdn_frontdoor_profile.this[0].response_timeout_seconds == 120
    error_message = "Front Door Profile should have 120 seconds response timeout by default"
  }
} 