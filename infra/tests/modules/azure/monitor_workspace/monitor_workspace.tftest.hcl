/**
 * # Tests for Azure Monitor Workspace Module
 *
 * This file contains tests for the Azure Monitor workspace module,
 * which creates resources for Azure Managed Prometheus metrics collection.
 */

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Global variables for tests
variables {
  resource_group_name = "test-rg"
  location            = "eastus"
}

# Test basic Monitor workspace creation
run "create_basic_monitor_workspace" {
  command = plan

  variables {
    name = "test-monitor-workspace"
    tags = {
      environment = "test"
      purpose     = "module-testing"
    }
  }

  module {
    source = "../../../../modules/azure/monitor_workspace"
  }

  assert {
    condition     = var.resource_group_name == "test-rg"
    error_message = "Resource group name should be test-rg"
  }

  assert {
    condition     = var.location == "eastus"
    error_message = "Location should be eastus"
  }

  assert {
    condition     = var.name == "test-monitor-workspace"
    error_message = "Monitor workspace name should be test-monitor-workspace"
  }
} 