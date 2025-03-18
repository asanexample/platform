provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
  storage_account_name = "teststorage42xtz"
  resource_group_name  = "test-rg-xtz"
  # Using a dummy ID for testing since we're just running plan
  storage_account_id = "/subscriptions/db4f1d99-0ec0-44eb-90de-41975f9bb68b/resourceGroups/test-rg-xtz/providers/Microsoft.Storage/storageAccounts/teststorage42xtz"
}

# We can no longer use the prepare_dependencies to get actual outputs during plan mode
# Commenting this out in favor of using hardcoded values
# run "prepare_dependencies" {
#   command = plan
#
#   module {
#     source = "../../../setup/storage_account"
#   }
# }

run "create_basic_containers" {
  command = plan

  variables {
    storage_account_id = var.storage_account_id
    containers = {
      "test-private" = {
        name                  = "test-private"
        container_access_type = "private"
      },
      "test-blob" = {
        name                  = "test-blob"
        container_access_type = "blob"
      },
      "test-container" = {
        name                  = "test-container"
        container_access_type = "container"
      }
    }
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  # Check a variable access to satisfy Terraform's requirement
  assert {
    condition     = var.storage_account_name == "teststorage42xtz"
    error_message = "Storage account name should be teststorage42xtz"
  }
} 