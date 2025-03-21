# Test file for Azure Storage Roles module
# Using Terraform 1.6+ testing framework

provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

# Global variables for all tests
variables {
  storage_account_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageacct"
}

# Test basic role assignments
run "create_basic_role_assignments" {
  command = plan

  variables {
    role_assignments = [
      {
        principal_id         = "00000000-0000-0000-0000-000000000000" # Test principal ID
        role_definition_name = "Storage Blob Data Contributor"
        description          = "Grant Storage Blob Data Contributor role to test user"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  # Assertions
  assert {
    condition     = length(var.role_assignments) == 1
    error_message = "Should have 1 role assignment defined"
  }
  
  assert {
    condition     = var.role_assignments[0].role_definition_name == "Storage Blob Data Contributor"
    error_message = "Role definition name should be Storage Blob Data Contributor"
  }
}

# Test multiple role assignments
run "create_multiple_role_assignments" {
  command = plan

  variables {
    role_assignments = [
      {
        principal_id         = "00000000-0000-0000-0000-000000000000" # Test principal ID
        role_definition_name = "Storage Blob Data Contributor"
        description          = "Grant Storage Blob Data Contributor role to test user"
      },
      {
        principal_id         = "11111111-1111-1111-1111-111111111111" # Test admin ID
        role_definition_name = "Storage Blob Data Owner"
        description          = "Grant Storage Blob Data Owner role to test admin"
      },
      {
        principal_id         = "22222222-2222-2222-2222-222222222222" # Test group ID
        role_definition_name = "Storage Blob Data Reader"
        description          = "Grant Storage Blob Data Reader role to test group"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  # Assertions
  assert {
    condition     = length(var.role_assignments) == 3
    error_message = "Should have 3 role assignments defined"
  }
  
  assert {
    condition     = contains(["Storage Blob Data Contributor", "Storage Blob Data Owner", "Storage Blob Data Reader"], var.role_assignments[0].role_definition_name)
    error_message = "Role definition names should be one of the expected values"
  }
}

# Test custom scope
run "create_role_with_custom_scope" {
  command = plan

  variables {
    role_assignments = [
      {
        principal_id         = "00000000-0000-0000-0000-000000000000" # Test principal ID
        role_definition_name = "Storage Blob Data Contributor"
        description          = "Grant Storage Blob Data Contributor role to test user"
        scope                = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg/providers/Microsoft.Storage/storageAccounts/teststorageacct/blobServices/default/containers/data"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_roles"
  }

  # Assertions
  assert {
    condition     = length(var.role_assignments) == 1
    error_message = "Should have 1 role assignment defined"
  }
  
  assert {
    condition     = endswith(var.role_assignments[0].scope, "containers/data")
    error_message = "Scope should be at the container level"
  }
} 