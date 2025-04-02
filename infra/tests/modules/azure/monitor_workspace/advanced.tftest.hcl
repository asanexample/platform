# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

/**
 * # Monitor Workspace Module - Advanced Test
 * 
 * This test verifies the advanced functionality of the Monitor Workspace module, including customizing
 * tags, different regions, and output values.
 */

# Test Monitor Workspace with custom tags
run "custom_tags_test" {
  command = plan

  variables {
    name                = "test-monitor-workspace"
    resource_group_name = "test-rg"
    location            = "eastus"
    tags = {
      Environment     = "Test"
      CostCenter      = "IT"
      ApplicationName = "Monitoring"
      Component       = "Prometheus"
    }
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Verify Monitor Workspace has custom tags
  assert {
    condition     = azurerm_monitor_workspace.this.tags.Environment == "Test"
    error_message = "Monitor Workspace should have the Environment tag set"
  }
  
  assert {
    condition     = azurerm_monitor_workspace.this.tags.CostCenter == "IT"
    error_message = "Monitor Workspace should have the CostCenter tag set"
  }
  
  assert {
    condition     = azurerm_monitor_workspace.this.tags.ApplicationName == "Monitoring"
    error_message = "Monitor Workspace should have the ApplicationName tag set"
  }
  
  assert {
    condition     = azurerm_monitor_workspace.this.tags.Component == "Prometheus"
    error_message = "Monitor Workspace should have the Component tag set"
  }
}

# Test Monitor Workspace in different regions
run "different_region_test" {
  command = plan

  variables {
    name                = "test-monitor-workspace"
    resource_group_name = "test-rg"
    location            = "westus2"
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  # Verify Monitor Workspace is created in the specified region
  assert {
    condition     = azurerm_monitor_workspace.this.location == "westus2"
    error_message = "Monitor Workspace should be in the westus2 location"
  }
}

# Test output values
run "output_values_test" {
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
  
  # Verify basic properties are set correctly
  assert {
    condition     = azurerm_monitor_workspace.this.name == "test-monitor-workspace"
    error_message = "Workspace name should match the input"
  }
} 