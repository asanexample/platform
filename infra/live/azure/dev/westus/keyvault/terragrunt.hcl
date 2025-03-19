# Terragrunt configuration for Azure Key Vault in westus region

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
  source = "${get_repo_root()}/infra/modules/azure/key_vault"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
    key_vault = "mock-kv"
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
  
  # Key Vault name
  key_vault_name = dependency.naming.outputs.key_vault
  
  # Key Vault configuration
  sku_name = "standard"
  enabled_for_deployment = false
  enabled_for_disk_encryption = true
  enabled_for_template_deployment = false
  enable_rbac_authorization = true
  purge_protection_enabled = true
  soft_delete_retention_days = 90
  
  # Network settings
  network_acls = {
    bypass = "AzureServices"
    default_action = "Deny"
    ip_rules = []
    virtual_network_subnet_ids = [
      dependency.networking.outputs.subnet_ids["az1-endpoint-subnet"]
    ]
  }
  
  # Private endpoint configuration
  private_endpoint = {
    subnet_id = dependency.networking.outputs.subnet_ids["az1-endpoint-subnet"]
    private_dns_zone_ids = []
  }
  
  # Initial secrets and access policies will be empty, to be filled by applications
  secrets = {}
  keys = {}
  access_policies = {}
  
  # Tags
  tags = local.tags
} 