# Terragrunt configuration for the storage account module

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Dependencies
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
    storage_account = "mocksa"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Configure the module source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/storage_account"
}

# Default inputs for the storage account module (overridden by environments)
inputs = {
  # Use naming module outputs
  resource_group_name = dependency.naming.outputs.resource_group
  name                = dependency.naming.outputs.storage_account
  
  # Use name components for internal reference in the module
  name_components = {
    prefix      = "vip"
    environment = "dev"
    region_abbv = "eus"
    instance    = "01"
  }
  
  # Default storage account settings
  location                 = "eastus"
  account_tier             = "Standard"
  account_replication_type = "LRS"
  network_rules = {
    default_action = "Allow"
    bypass         = ["AzureServices"]
    virtual_network_subnet_ids = []
  }
  containers = []
  
  # Default access settings
  allow_nested_items_to_be_public = false
  blob_public_access_enabled      = false
  
  # Tags
  tags = {
    ManagedBy   = "Terragrunt"
    Component   = "Storage"
  }
} 