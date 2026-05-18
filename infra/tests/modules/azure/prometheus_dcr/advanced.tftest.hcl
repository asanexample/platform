# Define provider configuration for the test runs
provider "azurerm" {
  features {}
  subscription_id                 = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id                       = "c945e155-be68-4477-b8d7-01939adbfe55"
  resource_provider_registrations = "none"
}

/**
 * # Prometheus DCR Module - Advanced Test
 * 
 * This test verifies the advanced functionality of the Prometheus DCR module
 * with custom names and tags.
 */

# Test Prometheus DCR creation with custom names
run "custom_names_test" {
  command = plan

  variables {
    resource_group_name  = "test-rg"
    location             = "eastus"
    monitor_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-monitor"

    name     = "custom-dcr-name"
    dce_name = "custom-dce-name"
  }

  module {
    source = "../../../../modules/azure/prometheus_dcr"
  }

  # Verify DCR is planned to be created
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.this) > 0
    error_message = "DCR should be planned for creation"
  }

  # Verify DCE is planned to be created
  assert {
    condition     = length(azurerm_monitor_data_collection_endpoint.this) > 0
    error_message = "DCE should be planned for creation"
  }
}

# Test Prometheus DCR creation with custom tags
run "custom_tags_test" {
  command = plan

  variables {
    resource_group_name  = "test-rg"
    location             = "eastus"
    monitor_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    tags = {
      Environment     = "Test"
      CostCenter      = "IT"
      ApplicationName = "Monitoring"
      Component       = "Prometheus"
    }
  }

  module {
    source = "../../../../modules/azure/prometheus_dcr"
  }

  # Verify DCR is planned to be created
  assert {
    condition     = length(azurerm_monitor_data_collection_rule.this) > 0
    error_message = "DCR should be planned for creation"
  }

  # Verify DCE is planned to be created
  assert {
    condition     = length(azurerm_monitor_data_collection_endpoint.this) > 0
    error_message = "DCE should be planned for creation"
  }
} 