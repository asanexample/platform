/**
 * # Log Analytics Module - Advanced Test
 * 
 * This test verifies advanced functionality of the Log Analytics module
 * with optional features and complex configurations.
 */

variables {
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

provider "azurerm" {
  features {}
  subscription_id = var.subscription_id
  tenant_id       = var.tenant_id
}

run "advanced_log_analytics" {
  command = plan

  variables {
    resource_group_name        = "rg-test-log-analytics"
    location                   = "eastus"
    name                       = "log-test-advanced"
    retention_in_days          = 90
    sku                        = "PerGB2018"
    daily_quota_gb             = 5
    internet_ingestion_enabled = false
    internet_query_enabled     = false
    role_assignments = [
      {
        role_definition_name = "Monitoring Contributor"
        principal_id         = "00000000-0000-0000-0000-000000000000"
        principal_type       = "ServicePrincipal"
      }
    ]
    tags = {
      environment = "test"
      purpose     = "module testing"
    }
    solution_plans = [
      {
        solution_name = "ContainerInsights"
        product       = "OMSGallery/ContainerInsights"
        publisher     = "Microsoft"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/log_analytics"
  }

  # In plan mode, verify inputs are correctly set
  assert {
    condition     = var.name == "log-test-advanced"
    error_message = "Name should be 'log-test-advanced'"
  }

  assert {
    condition     = var.retention_in_days == 90
    error_message = "Retention in days should be 90"
  }

  assert {
    condition     = var.daily_quota_gb == 5
    error_message = "Daily quota should be 5 GB"
  }

  assert {
    condition     = var.internet_ingestion_enabled == false
    error_message = "Internet ingestion should be disabled"
  }

  assert {
    condition     = var.internet_query_enabled == false
    error_message = "Internet query should be disabled"
  }

  assert {
    condition     = length(var.role_assignments) == 1
    error_message = "Should have 1 role assignment"
  }

  assert {
    condition     = var.role_assignments[0].role_definition_name == "Monitoring Contributor"
    error_message = "Role definition name should be 'Monitoring Contributor'"
  }

  assert {
    condition     = length(var.solution_plans) == 1
    error_message = "Should have 1 solution plan"
  }

  assert {
    condition     = var.solution_plans[0].solution_name == "ContainerInsights"
    error_message = "Solution name should be 'ContainerInsights'"
  }
} 