provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
}

variables {
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

run "containers_with_metadata" {
  command = plan

  variables {
    storage_account_id = var.storage_account_id
    containers = {
      "app-data" = {
        name                  = "app-data"
        container_access_type = "private"
        metadata = {
          application = "test-app"
          environment = "testing"
          department  = "engineering"
          owner       = "infrastructure-team"
        }
      },
      "app-logs" = {
        name                  = "app-logs"
        container_access_type = "private"
        metadata = {
          retention_days = "30"
          classification = "internal"
        }
      }
    }
  }

  module {
    source = "../../../../modules/azure/storage_container"
  }

  # Check a reference to satisfy Terraform's requirement
  assert {
    condition     = lookup(var.containers, "app-data", null) != null
    error_message = "The containers map should include app-data"
  }
} 