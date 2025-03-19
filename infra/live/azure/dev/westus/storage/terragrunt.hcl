# Terragrunt configuration for Azure storage in westus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env         = local.common_vars.locals.env
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = "westus"
  region_abbv = "wus"
  tags        = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the actual Terraform module as the source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/storage_account"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
    storage_account = "mocksa"
  }
}

dependency "networking" {
  config_path = "../networking"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    subnet_ids = {
      "az1-endpoint-subnet" = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet/subnets/az1-endpoint-subnet"
    }
  }
}

# Specify inputs specific to this module
inputs = {
  # Resource group
  resource_group_name = dependency.naming.outputs.resource_group
  location = local.region
  
  # Storage account name
  name = dependency.naming.outputs.storage_account
  
  # Storage account configuration
  account_tier = "Standard"
  account_replication_type = "LRS"
  
  # Network rules
  network_rules = {
    default_action = "Deny"
    bypass = ["AzureServices"]
    virtual_network_subnet_ids = [
      dependency.networking.outputs.subnet_ids["az1-endpoint-subnet"]
    ]
  }
  
  # Containers
  containers = {
    "data" = {
      name = "data"
      container_access_type = "private"
    }
    "logs" = {
      name = "logs"
      container_access_type = "private"
    }
  }
  
  # Security settings
  allow_nested_items_to_be_public = false
  blob_public_access_enabled = false
  
  # Tags
  tags = local.tags
} 