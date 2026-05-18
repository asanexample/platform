# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id                 = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id                       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

/**
 * # Monitor Workspace Module - Basic Test
 * 
 * This test verifies the basic functionality of the Monitor Workspace module
 * with minimal configuration.
 */

# Test basic Monitor Workspace creation
run "basic_monitor_workspace" {
  command = plan

  variables {
    name                = "test-monitor-workspace"
    resource_group_name = "test-rg"
    location            = "eastus"
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Verify Monitor Workspace is created with the correct name
  assert {
    condition     = azurerm_monitor_workspace.this.name == "test-monitor-workspace"
    error_message = "Monitor Workspace should be created with the specified name"
  }

  # Verify resource group and location
  assert {
    condition     = azurerm_monitor_workspace.this.resource_group_name == "test-rg"
    error_message = "Monitor Workspace should be in the correct resource group"
  }

  assert {
    condition     = azurerm_monitor_workspace.this.location == "eastus"
    error_message = "Monitor Workspace should be in the correct location"
  }
} 