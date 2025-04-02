/**
 * # Azure Resource Group Module
 *
 * This module creates an Azure resource group with standardized naming.
 * Resource groups are logical containers for Azure resources and provide
 * a way to manage permissions, billing, and resource lifecycle.
 */

# Create an Azure Resource Group
resource "azurerm_resource_group" "rg" {
  # Name will be provided by Terragrunt using the naming module
  name     = var.name
  location = var.location
  tags     = var.tags
} 