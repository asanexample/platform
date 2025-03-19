# Terragrunt configuration for the key vault module

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
    key_vault = "mock-kv"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Configure the module source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/key_vault"
}

# Default inputs for the key vault module (overridden by environments)
inputs = {
  # Use naming module outputs
  resource_group_name = dependency.naming.outputs.resource_group
  name                = dependency.naming.outputs.key_vault
  
  # Use name components for internal reference in the module
  name_components = {
    prefix      = "vip"
    environment = "dev"
    region_abbv = "eus"
    instance    = "01"
  }
  
  # Default key vault settings
  location                    = "eastus"
  enable_rbac_authorization   = true
  enabled_for_disk_encryption = true
  purge_protection_enabled    = true
  soft_delete_retention_days  = 90
  sku_name                    = "standard"
  
  # Default network settings (can be overridden)
  public_network_access_enabled = false
  
  # Default to empty access policies (will be set as needed)
  access_policies = []
  
  # Default to no private endpoint
  private_endpoint = {}
  
  # Tags
  tags = {
    ManagedBy   = "Terragrunt"
    Component   = "KeyVault"
  }
} 