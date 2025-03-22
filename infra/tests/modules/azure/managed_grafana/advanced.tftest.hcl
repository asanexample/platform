/**
 * # Managed Grafana Module - Advanced Test
 * 
 * This test verifies advanced features of the managed grafana module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Test with admin group assignments
run "admin_group_assignment_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    admin_group_object_ids  = [
      "11111111-1111-1111-1111-111111111111",
      "22222222-2222-2222-2222-222222222222"
    ]
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify Grafana resource is created
  assert {
    condition     = azurerm_dashboard_grafana.grafana.name == "test-grafana"
    error_message = "Grafana resource should be created with the correct name"
  }
  
  # Verify admin group role assignments
  assert {
    condition     = length(azurerm_role_assignment.grafana_admin_groups) == 2
    error_message = "Two admin group role assignments should be created"
  }
}

# Test with admin user assignments
run "admin_user_assignment_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    admin_user_object_ids   = [
      "33333333-3333-3333-3333-333333333333",
      "44444444-4444-4444-4444-444444444444"
    ]
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify Grafana resource is created
  assert {
    condition     = azurerm_dashboard_grafana.grafana.name == "test-grafana"
    error_message = "Grafana resource should be created with the correct name"
  }
  
  # Verify admin user role assignments
  assert {
    condition     = length(azurerm_role_assignment.grafana_admin_users) == 2
    error_message = "Two admin user role assignments should be created"
  }
}

# Test with both admin group and user assignments
run "combined_admin_assignment_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    admin_group_object_ids  = [
      "11111111-1111-1111-1111-111111111111"
    ]
    admin_user_object_ids   = [
      "33333333-3333-3333-3333-333333333333"
    ]
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify Grafana resource is created
  assert {
    condition     = azurerm_dashboard_grafana.grafana.name == "test-grafana"
    error_message = "Grafana resource should be created with the correct name"
  }
  
  # Verify admin group and user role assignments
  assert {
    condition     = length(azurerm_role_assignment.grafana_admin_groups) == 1
    error_message = "One admin group role assignment should be created"
  }
  
  assert {
    condition     = length(azurerm_role_assignment.grafana_admin_users) == 1
    error_message = "One admin user role assignment should be created"
  }
}

# Test with custom tags
run "custom_tags_test" {
  command = plan

  variables {
    name                    = "test-grafana"
    resource_group_name     = "test-rg"
    location                = "eastus"
    prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
    tags = {
      Environment     = "Test"
      CostCenter      = "IT"
      ApplicationName = "Monitoring"
    }
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  # Verify Grafana resource is created with custom tags
  assert {
    condition     = azurerm_dashboard_grafana.grafana.tags.Environment == "Test"
    error_message = "Grafana should have the Environment tag set"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.tags.CostCenter == "IT"
    error_message = "Grafana should have the CostCenter tag set"
  }
  
  assert {
    condition     = azurerm_dashboard_grafana.grafana.tags.ApplicationName == "Monitoring"
    error_message = "Grafana should have the ApplicationName tag set"
  }
} 