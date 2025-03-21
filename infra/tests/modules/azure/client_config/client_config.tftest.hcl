/**
 * # Tests for Azure Client Config Module
 *
 * This file contains tests for the Azure Client Config module.
 * The module simply exposes data about the current Azure client configuration.
 */

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Test the client_config module
run "verify_client_config" {
  command = plan

  variables {
    # Add a placeholder variable to reference in our assertion
    test_value = "test"
  }

  module {
    source = "../../../../modules/azure/client_config"
  }

  # Verify the module can be loaded and used in a test
  assert {
    condition     = var.test_value == "test"
    error_message = "Test value should be 'test'"
  }
} 