/**
 * # Storage Container Module - Validation Test
 * 
 * This test verifies the validation rules for the storage container module.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Setup resources needed for testing
run "setup_resources" {
  command = plan

  module {
    source = "../../../setup/storage_container_test_setup"
  }
}

# Test valid container name validation
run "valid_container_name_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    containers = {
      "valid-container" = {
        name                 = "valid-container" # Valid name with lowercase letters, numbers, and dashes
        container_access_type = "private"
      }
    }
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  assert {
    condition     = length(var.containers) > 0 && var.containers["valid-container"].name == "valid-container"
    error_message = "Container with valid name should be accepted"
  }
}

# Test valid container access type validation
run "valid_access_type_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    containers = {
      "blob-access" = {
        name                 = "blob-access"
        container_access_type = "blob" # Valid access type
      },
      "container-access" = {
        name                 = "container-access"
        container_access_type = "container" # Valid access type
      },
      "private-access" = {
        name                 = "private-access"
        container_access_type = "private" # Valid access type (default)
      }
    }
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  assert {
    condition     = length(var.containers) == 3 && var.containers["blob-access"].container_access_type == "blob" && var.containers["container-access"].container_access_type == "container" && var.containers["private-access"].container_access_type == "private"
    error_message = "Containers with valid access types should be accepted"
  }
}

# Test valid role assignment validation
run "valid_role_assignment_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    containers = {
      "data" = {
        name                 = "data"
        container_access_type = "private"
      }
    }
    role_assignments = [
      {
        container_key        = "data" # Valid container key that exists in containers
        principal_id         = "00000000-0000-0000-0000-000000000000" # Mock principal ID
        role_definition_name = "Storage Blob Data Contributor"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  assert {
    condition     = length(var.role_assignments) == 1 && var.role_assignments[0].container_key == "data" && var.role_assignments[0].role_definition_name == "Storage Blob Data Contributor"
    error_message = "Role assignment with valid container key should be accepted"
  }
} 