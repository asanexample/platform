/**
 * # Client Config Module - Advanced Test
 * 
 * This test verifies the advanced functionality of the client config module,
 * including verification of output formats and relationships.
 */

# Provider configuration with Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

# Advanced test for output format validation
run "output_format_validation" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }

  # Validate subscription ID format
  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.subscription_id))
    error_message = "Subscription ID should be in UUID format"
  }
  
  # Validate tenant ID format
  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.tenant_id))
    error_message = "Tenant ID should be in UUID format"
  }
  
  # Validate client ID format
  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.client_id)) || output.client_id == ""
    error_message = "Client ID should be in UUID format or empty"
  }
  
  # Validate object ID format
  assert {
    condition     = can(regex("^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$", output.object_id)) || output.object_id == ""
    error_message = "Object ID should be in UUID format or empty"
  }
}

# Test for ensuring all values are populated
run "value_population_check" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }

  # Check that tenant ID is always populated
  assert {
    condition     = output.tenant_id != ""
    error_message = "Tenant ID should always be populated"
  }
  
  # Check that subscription ID is always populated
  assert {
    condition     = output.subscription_id != ""
    error_message = "Subscription ID should always be populated"
  }
} 