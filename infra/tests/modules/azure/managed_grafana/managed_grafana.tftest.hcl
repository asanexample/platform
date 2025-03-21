/**
 * # Tests for Azure Managed Grafana Module
 *
 * This file contains tests for the Azure Managed Grafana module,
 * which creates and configures Azure Managed Grafana instances.
 */

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Global variables for tests
variables {
  resource_group_name    = "test-rg"
  location               = "eastus"
  prometheus_workspace_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Monitor/accounts/test-prometheus"
}

# Test basic Grafana instance creation
run "create_basic_grafana" {
  command = plan

  variables {
    name = "test-grafana"
    tags = {
      environment = "test"
      purpose     = "module-testing"
    }
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
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
    condition     = var.name == "test-grafana"
    error_message = "Grafana name should be test-grafana"
  }
}

# Test Grafana with custom settings
run "create_grafana_custom_settings" {
  command = plan

  variables {
    name                           = "test-grafana-custom"
    api_key_enabled                = false
    public_network_access_enabled  = false
    deterministic_outbound_ip_enabled = true
    zone_redundancy_enabled        = true
    grafana_major_version          = "9"
    
    # Admin access settings
    admin_group_object_ids         = ["00000000-0000-0000-0000-000000000001"]
    admin_user_object_ids          = ["00000000-0000-0000-0000-000000000002"]
    
    tags = {
      environment = "production"
      purpose     = "monitoring"
    }
  }

  module {
    source = "../../../../modules/azure/managed_grafana"
  }

  assert {
    condition     = var.name == "test-grafana-custom"
    error_message = "Grafana name should be test-grafana-custom"
  }

  assert {
    condition     = var.api_key_enabled == false
    error_message = "API key enabled should be false"
  }

  assert {
    condition     = var.public_network_access_enabled == false
    error_message = "Public network access enabled should be false"
  }

  assert {
    condition     = var.grafana_major_version == "9"
    error_message = "Grafana major version should be 9"
  }
} 