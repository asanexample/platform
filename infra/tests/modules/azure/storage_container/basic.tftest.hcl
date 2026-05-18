/**
 * # Storage Container Module - Basic Test
 * 
 * This test verifies the basic functionality of the storage container module 
 * with a minimal configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id       = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Setup resources needed for testing
run "setup_resources" {
  command = plan

  module {
    source = "../../../setup/storage_container_test_setup"
  }
}

# Test basic container creation
run "basic_container_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    containers = {
      "data" = {
        name                  = "data"
        container_access_type = "private"
      }
    }
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  assert {
    condition     = length(output.container_names) == 1
    error_message = "Should create exactly one container"
  }

  assert {
    condition     = output.container_names[0] == "data"
    error_message = "Container name should be 'data'"
  }

  assert {
    condition     = lookup(output.containers, "data", null) != null
    error_message = "Container 'data' should exist in outputs"
  }

  assert {
    condition     = contains(keys(output.container_ids), "data")
    error_message = "Container 'data' should have an ID"
  }
} 