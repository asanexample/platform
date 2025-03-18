/**
 * # Azure Hosting Module
 * 
 * This module deploys both networking and storage resources in a single resource group,
 * providing a complete hosting infrastructure for applications. It integrates these
 * components to ensure secure network access to storage resources.
 */

# Create a single resource group for both networking and storage
resource "azurerm_resource_group" "hosting_rg" {
  name     = var.resource_group_name
  location = var.location
  tags     = var.tags
}

# Deploy networking infrastructure
module "network" {
  source = "../networking"

  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = azurerm_resource_group.hosting_rg.location
  vnet_name           = var.vnet_name
  address_space       = var.address_space
  subnets             = var.subnets
  dns_servers         = var.dns_servers

  tags = var.tags
}

# Deploy storage with private network integration
module "storage_account" {
  source = "../storage_account"

  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = azurerm_resource_group.hosting_rg.location

  name_components          = var.storage_name_components
  account_tier             = var.storage_account_tier
  account_replication_type = var.storage_replication_type

  # Configure network rules to only allow access from VNet
  network_rules = {
    default_action = var.storage_network_default_action
    bypass         = var.storage_network_bypass
    virtual_network_subnet_ids = [
      for subnet_name in var.storage_allowed_subnets :
      module.network.subnet_ids[subnet_name]
    ]
  }

  containers = var.storage_containers

  # Enable public access if needed
  allow_nested_items_to_be_public = var.storage_allow_public
  blob_public_access_enabled      = var.storage_allow_public

  # Configure CORS if needed
  cors_rules = var.storage_cors_rules

  tags = var.tags
} 