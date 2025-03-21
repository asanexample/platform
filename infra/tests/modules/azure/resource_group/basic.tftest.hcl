/**
 * # Resource Group Module - Basic Test
 * 
 * This test verifies the basic functionality of the resource group module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for resource group creation with minimal configuration
run "basic_resource_group" {
  command = plan

  variables {
    name     = "test-rg"
    location = "eastus"
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/resource_group"
  }

  # Validate resource group properties
  assert {
    condition     = output.name == "test-rg"
    error_message = "Resource group name doesn't match expected value"
  }

  assert {
    condition     = output.location == "eastus"
    error_message = "Resource group location doesn't match expected value"
  }
} 