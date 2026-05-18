/**
 * # Storage Roles Module - Basic Test
 * 
 * This test verifies the basic functionality of the storage roles module 
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

# Get the current client configuration for role assignments
run "get_client_config" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }
}

# Test basic role assignment
run "basic_role_assignment_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    role_assignments = [
      {
        principal_id         = run.get_client_config.object_id
        role_definition_name = "Storage Blob Data Reader"
        description          = "Read access to storage account"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  assert {
    condition     = length(output.role_assignment_ids) == 1
    error_message = "Should create exactly one role assignment"
  }
} 