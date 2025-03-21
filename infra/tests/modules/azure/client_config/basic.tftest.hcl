/**
 * # Client Config Module - Basic Test
 * 
 * This test verifies the functionality of the client config module
 * which retrieves the current Azure client configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for client config retrieval
run "client_config_retrieval" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }

  # Validate client config outputs
  assert {
    condition     = output.tenant_id == "c945e155-be68-4477-b8d7-01939adbfe55"
    error_message = "Tenant ID doesn't match expected value"
  }
  
  assert {
    condition     = output.subscription_id == "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
    error_message = "Subscription ID doesn't match expected value"
  }
  
  assert {
    condition     = output.client_id != ""
    error_message = "Client ID should not be empty"
  }
  
  assert {
    condition     = output.object_id != ""
    error_message = "Object ID should not be empty"
  }
} 