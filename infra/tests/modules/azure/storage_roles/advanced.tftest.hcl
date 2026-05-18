/**
 * # Storage Roles Module - Advanced Test
 * 
 * This test verifies the advanced functionality of the storage roles module 
 * with multiple role assignments and different scopes.
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

# Setup containers for scoped role assignments
run "setup_containers" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    containers = {
      "data" = {
        name                  = "data"
        container_access_type = "private"
      },
      "logs" = {
        name                  = "logs"
        container_access_type = "private"
      }
    }
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }
}

# Get the current client configuration for role assignments
run "get_client_config" {
  command = plan

  module {
    source = "../../../../modules/azure/client_config"
  }
}

# Test advanced role assignments with different scopes
run "advanced_role_assignment_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    role_assignments = [
      {
        # Account-level Contributor role
        principal_id         = run.get_client_config.object_id
        role_definition_name = "Storage Blob Data Contributor"
        description          = "Full access to storage account"
      },
      {
        # Data container-level Reader role
        principal_id         = run.get_client_config.object_id
        role_definition_name = "Storage Blob Data Reader"
        description          = "Read access to data container"
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount/blobServices/default/containers/data"
      },
      {
        # Logs container-level Contributor role with role definition ID
        principal_id       = run.get_client_config.object_id
        role_definition_id = "/subscriptions/${run.get_client_config.subscription_id}/providers/Microsoft.Authorization/roleDefinitions/ba92f5b4-2d11-453d-a403-e96b0029c9fe" # Storage Blob Data Contributor
        description        = "Full access to logs container"
        scope              = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount/blobServices/default/containers/logs"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  assert {
    condition     = length(output.role_assignment_ids) == 3
    error_message = "Should create exactly three role assignments"
  }
} 