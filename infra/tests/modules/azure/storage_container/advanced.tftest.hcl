/**
 * # Storage Container Module - Advanced Test
 * 
 * This test verifies the advanced functionality of the storage container module 
 * with multiple containers, different access types, and role assignments.
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

# Test advanced container creation with multiple containers and role assignments
run "advanced_container_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"

    containers = {
      "data" = {
        name                  = "data"
        container_access_type = "private"
        metadata = {
          "environment" = "test"
          "purpose"     = "data storage"
        }
      },
      "logs" = {
        name                  = "logs"
        container_access_type = "private"
        metadata = {
          "retention" = "30days"
          "type"      = "application-logs"
        }
      },
      "public" = {
        name                  = "public"
        container_access_type = "blob"
        metadata = {
          "access"  = "read-only"
          "content" = "public-docs"
        }
      }
    }

    role_assignments = [
      {
        container_key        = "data"
        principal_id         = run.get_client_config.object_id
        role_definition_name = "Storage Blob Data Contributor"
        description          = "Full access to data container"
      },
      {
        container_key        = "logs"
        principal_id         = run.get_client_config.object_id
        role_definition_name = "Storage Blob Data Reader"
        description          = "Read access to logs container"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  assert {
    condition     = length(output.container_names) == 3
    error_message = "Should create exactly three containers"
  }

  assert {
    condition     = contains(output.container_names, "data") && contains(output.container_names, "logs") && contains(output.container_names, "public")
    error_message = "Should create containers with names 'data', 'logs', and 'public'"
  }

  assert {
    condition     = output.containers["public"].container_access_type == "blob"
    error_message = "Public container should have 'blob' access type"
  }

  assert {
    condition     = output.containers["data"].container_access_type == "private" && output.containers["logs"].container_access_type == "private"
    error_message = "Data and logs containers should have 'private' access type"
  }

  assert {
    condition     = length(output.role_assignments) == 2
    error_message = "Should create exactly two role assignments"
  }

  assert {
    condition     = contains(keys(output.container_resource_manager_ids), "data") && contains(keys(output.container_resource_manager_ids), "logs")
    error_message = "Should have resource manager IDs for data and logs containers"
  }
} 