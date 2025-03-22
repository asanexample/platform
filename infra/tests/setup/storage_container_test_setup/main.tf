/**
 * # Storage Container Test Setup
 * 
 * This module creates the necessary resources for testing the storage container module,
 * including a resource group and storage account.
 */

# Create a resource group for testing
resource "azurerm_resource_group" "test" {
  name     = "rg-storage-container-test"
  location = "eastus"
  tags = {
    Environment = "Test"
    Module      = "Storage Container"
  }
}

# Create a storage account for testing
resource "azurerm_storage_account" "test" {
  name                     = "teststoragecontainer"
  resource_group_name      = azurerm_resource_group.test.name
  location                 = azurerm_resource_group.test.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
  tags = {
    Environment = "Test"
    Module      = "Storage Container"
  }
}

# Output the storage account ID for use in tests
output "storage_account_id" {
  description = "The ID of the storage account created for testing"
  value       = azurerm_storage_account.test.id
}

# Output the storage account name for use in tests
output "storage_account_name" {
  description = "The name of the storage account created for testing"
  value       = azurerm_storage_account.test.name
}

# Output the resource group name for use in tests
output "resource_group_name" {
  description = "The name of the resource group created for testing"
  value       = azurerm_resource_group.test.name
} 