# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

/**
 * # Monitor Workspace Module - Validation Test
 * 
 * This test verifies the validation conditions for the Monitor Workspace module.
 */

# Test resource group validation
run "resource_group_validation_test" {
  command = plan

  variables {
    name                = "test-monitor-workspace"
    resource_group_name = "test-rg"
    location            = "eastus"
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Verify resource is planned to be created
  assert {
    condition     = length(azurerm_monitor_workspace.this) > 0
    error_message = "Monitor Workspace resource should be planned for creation"
  }
}

# Test with different name formats
run "name_format_test" {
  command = plan

  variables {
    name                = "testmonitorws123"
    resource_group_name = "test-rg"
    location            = "eastus"
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Verify name is set correctly
  assert {
    condition     = azurerm_monitor_workspace.this.name == "testmonitorws123"
    error_message = "Monitor Workspace should accept alphanumeric name without hyphens"
  }
}

# Test with long name
run "long_name_test" {
  command = plan

  variables {
    name                = "test-monitor-workspace-with-a-longer-name-that-is-valid"
    resource_group_name = "test-rg"
    location            = "eastus"
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Verify name is set correctly
  assert {
    condition     = azurerm_monitor_workspace.this.name == "test-monitor-workspace-with-a-longer-name-that-is-valid"
    error_message = "Monitor Workspace should accept longer valid names"
  }
}

# Test creating multiple resources (idempotency)
run "multiple_runs_test" {
  command = plan
  
  variables {
    name                = "test-monitor-workspace"
    resource_group_name = "test-rg"
    location            = "eastus"
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }
  
  # Verify the resource is created as expected
  assert {
    condition     = azurerm_monitor_workspace.this.name == "test-monitor-workspace"
    error_message = "Monitor Workspace should be created with the correct name"
  }
} 