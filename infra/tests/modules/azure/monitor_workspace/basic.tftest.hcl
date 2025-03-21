/**
 * # Monitor Workspace Module - Basic Test
 * 
 * This test verifies the basic functionality of the Monitor workspace module
 * with minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Basic test for Monitor workspace creation with minimal configuration
run "basic_monitor_workspace" {
  command = plan

  variables {
    name                = "test-monitor-ws"
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Basic tags
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Validate Monitor workspace properties
  assert {
    condition     = output.name == "test-monitor-ws"
    error_message = "Monitor workspace name doesn't match expected value"
  }
  
  assert {
    condition     = output.dcr_id != ""
    error_message = "Data Collection Rule ID should not be empty"
  }
  
  assert {
    condition     = output.dce_id != ""
    error_message = "Data Collection Endpoint ID should not be empty"
  }
} 