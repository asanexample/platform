/**
 * # Storage Account Module - Advanced Test
 * 
 * This test verifies advanced functionality of the storage account module
 * including containers, network rules, and CORS configuration.
 */

# Provider configuration with actual Azure credentials
provider "azurerm" {
  features {}
  subscription_id = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  tenant_id = "c945e155-be68-4477-b8d7-01939adbfe55"
}

# Advanced test for storage account with containers, network rules, and CORS
run "advanced_storage_account" {
  command = plan

  variables {
    resource_group_name = "test-rg"
    location            = "eastus"
    
    # Explicit name
    name = "teststorageadv2023"
    
    # Advanced storage account configuration
    account_kind             = "StorageV2"
    account_tier             = "Standard"
    account_replication_type = "ZRS"
    access_tier              = "Cool"
    
    # Security settings
    min_tls_version                 = "TLS1_2"
    allow_nested_items_to_be_public = false
    shared_access_key_enabled       = true
    blob_public_access_enabled      = false
    public_network_access_enabled   = true
    
    # Container configuration
    create_containers = true
    containers = {
      data = {
        name = "data",
        container_access_type = "private"
      },
      logs = {
        name = "logs",
        container_access_type = "private"
      }
    }
    
    # Network rules
    network_rules = {
      default_action = "Deny"
      bypass = ["AzureServices", "Logging", "Metrics"]
      ip_rules = ["203.0.113.0/24", "198.51.100.0/24"]
      virtual_network_subnet_ids = []
    }
    
    # CORS configuration
    cors_rules = [
      {
        allowed_headers = ["*"]
        allowed_methods = ["GET", "PUT", "POST"]
        allowed_origins = ["https://example.com", "https://test.example.com"]
        exposed_headers = ["Content-Length", "Content-Type"]
        max_age_in_seconds = 200
      }
    ]
    
    # Lifecycle rules
    lifecycle_rules = [
      {
        name = "deleteAfter30Days"
        enabled = true
        filters = {
          prefix_match = ["logs/"]
          blob_types = ["blockBlob"]
        }
        actions = {
          base_blob = {
            delete_after_days_since_modification_greater_than = 30
          }
        }
      }
    ]
    
    # Versioning and delete retention
    blob_versioning_enabled = true
    blob_delete_retention_days = 7
    container_delete_retention_days = 7
    
    # Tags
    tags = {
      environment = "test"
      purpose     = "advanced module testing"
      cost-center = "engineering"
    }
  }

  module {
    source = "../../../../modules/azure/storage_account"
  }

  # Validate storage account properties
  assert {
    condition     = output.name == "teststorageadv2023"
    error_message = "Storage account name doesn't match expected value"
  }

  assert {
    condition     = length(output.containers) == 2
    error_message = "Should have created 2 containers"
  }

  assert {
    condition     = contains(keys(output.containers), "data")
    error_message = "Should have created a 'data' container"
  }

  assert {
    condition     = contains(keys(output.containers), "logs")
    error_message = "Should have created a 'logs' container"
  }
} 