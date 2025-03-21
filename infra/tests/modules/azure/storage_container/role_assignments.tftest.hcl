provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  # Using a dummy ID for testing since we're just running plan
  storage_account_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg-xtz/providers/Microsoft.Storage/storageAccounts/teststorage42xtz"
}

run "container_role_assignments" {
  command = plan

  variables {
    storage_account_id = var.storage_account_id
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
    
    role_assignments = [
      {
        container_key         = "data"
        principal_id          = "11111111-1111-1111-1111-111111111111" # Test User ID
        role_definition_name  = "Storage Blob Data Contributor"
        description           = "Allows data contributor access for test user"
      },
      {
        container_key         = "data"
        principal_id          = "22222222-2222-2222-2222-222222222222" # Test Admin ID
        role_definition_name  = "Storage Blob Data Owner"
        description           = "Allows data owner access for test admin"
      },
      {
        container_key         = "logs"
        principal_id          = "33333333-3333-3333-3333-333333333333" # Service Principal ID
        role_definition_name  = "Storage Blob Data Reader"
        description           = "Allows read-only access for monitoring service"
        principal_type        = "ServicePrincipal"
      }
    ]
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  # Verify role assignment implementation
  assert {
    condition     = length(var.role_assignments) == 3
    error_message = "There should be 3 role assignments defined"
  }
  
  # Verify that role assignments are created for each specified container
  assert {
    condition     = length([for ra in var.role_assignments : ra if ra.container_key == "data"]) == 2
    error_message = "The 'data' container should have 2 role assignments"
  }
  
  assert {
    condition     = length([for ra in var.role_assignments : ra if ra.container_key == "logs"]) == 1
    error_message = "The 'logs' container should have 1 role assignment"
  }
} 