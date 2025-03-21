/**
 * # Test Setup - Storage Account
 * 
 * This module creates a storage account for testing purposes.
 * It is used as a dependency in various module tests.
 */

provider "azurerm" {
  features {}
}

resource "random_string" "suffix" {
  length  = 8
  special = false
  upper   = false
}

variable "storage_account_name" {
  description = "The name of the storage account"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  default     = null
}

locals {
  resource_group_name  = var.resource_group_name != null ? var.resource_group_name : "test-storage-rg-${random_string.suffix.result}"
  storage_account_name = var.storage_account_name != null ? var.storage_account_name : "testsa${random_string.suffix.result}"
}

resource "azurerm_resource_group" "test_rg" {
  name     = local.resource_group_name
  location = "eastus"
}

resource "azurerm_storage_account" "test_sa" {
  name                     = local.storage_account_name
  resource_group_name      = azurerm_resource_group.test_rg.name
  location                 = azurerm_resource_group.test_rg.location
  account_tier             = "Standard"
  account_replication_type = "LRS"
}

output "resource_group_id" {
  value = azurerm_resource_group.test_rg.id
}

output "resource_group_name" {
  value = azurerm_resource_group.test_rg.name
}

output "storage_account_id" {
  value = azurerm_storage_account.test_sa.id
}

output "storage_account_name" {
  value = azurerm_storage_account.test_sa.name
} 