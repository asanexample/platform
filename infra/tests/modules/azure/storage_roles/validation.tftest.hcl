/**
 * # Storage Roles Module - Validation Test
 * 
 * This test verifies the validation rules for the storage roles module.
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

# Test valid role assignment with role_definition_name
run "valid_role_definition_name_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    role_assignments = [
      {
        principal_id         = "00000000-0000-0000-0000-000000000000" # Mock principal ID
        role_definition_name = "Storage Blob Data Reader"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  assert {
    condition     = length(var.role_assignments) == 1 && var.role_assignments[0].role_definition_name == "Storage Blob Data Reader"
    error_message = "Role assignment with valid role_definition_name should be accepted"
  }
}

# Test valid role assignment with role_definition_id
run "valid_role_definition_id_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    role_assignments = [
      {
        principal_id        = "00000000-0000-0000-0000-000000000000" # Mock principal ID
        role_definition_id  = "00000000-0000-0000-0000-000000000000" # Mock role definition ID
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  assert {
    condition     = length(var.role_assignments) == 1 && var.role_assignments[0].role_definition_id == "00000000-0000-0000-0000-000000000000"
    error_message = "Role assignment with valid role_definition_id should be accepted"
  }
}

# Test valid role assignment with custom scope
run "valid_custom_scope_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    role_assignments = [
      {
        principal_id         = "00000000-0000-0000-0000-000000000000" # Mock principal ID
        role_definition_name = "Storage Blob Data Reader"
        scope                = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount/blobServices/default/containers/data"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  assert {
    condition     = length(var.role_assignments) == 1 && contains(keys(var.role_assignments[0]), "scope")
    error_message = "Role assignment with valid custom scope should be accepted"
  }
}

# Test valid role assignment with description
run "valid_description_test" {
  command = plan

  variables {
    storage_account_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageaccount"
    role_assignments = [
      {
        principal_id         = "00000000-0000-0000-0000-000000000000" # Mock principal ID
        role_definition_name = "Storage Blob Data Reader"
        description          = "Test role assignment for validation"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  assert {
    condition     = length(var.role_assignments) == 1 && var.role_assignments[0].description == "Test role assignment for validation"
    error_message = "Role assignment with valid description should be accepted"
  }
} 