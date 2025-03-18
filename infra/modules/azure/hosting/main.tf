/**
 * # Azure Hosting Module
 * 
 * This module deploys both networking and storage resources in a single resource group,
 * providing a complete hosting infrastructure for applications. It integrates these
 * components to ensure secure network access to storage resources.
 *
 * IMPORTANT: This module always uses the naming module for standardized resource naming.
 * The required parameters for naming are: stage and region_abbv. The optional parameters
 * are: prefix (defaults to "vip") and customer (for customer-specific resources).
 */

# Use naming module for standardized resource naming
module "naming" {
  source      = "../naming"
  
  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
}

locals {
  # Always use naming module outputs for resource names
  resource_group_name = module.naming.resource_group
  vnet_name           = module.naming.virtual_network
  storage_account_name = module.naming.storage_account

  # Create a map of subnet names using the naming module
  subnet_name_map = {
    for subnet_key in keys(var.subnets) :
    subnet_key => "${module.naming.subnet}-${subnet_key}-${var.region_abbv}"
  }
}

# Create a single resource group for both networking and storage
resource "azurerm_resource_group" "hosting_rg" {
  name     = local.resource_group_name
  location = var.location
  tags     = var.tags
}

# Deploy networking infrastructure
module "network" {
  source = "../networking"

  resource_group_name = azurerm_resource_group.hosting_rg.name
  location            = azurerm_resource_group.hosting_rg.location
  vnet_name           = local.vnet_name
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

  # Always use naming module for storage account name
  name                = local.storage_account_name
  name_components     = {
    # Default values for the storage module's internal reference
    prefix      = "tmp" 
    environment = var.stage
    region_abbv = var.region_abbv
    instance    = "01"
  }
  
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