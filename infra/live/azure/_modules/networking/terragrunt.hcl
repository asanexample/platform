# Terragrunt configuration for the networking module

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
    virtual_network = "mock-vnet"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Configure the module source
terraform {
  source = "${get_repo_root()}/infra/modules/azure/networking"
}

# Default inputs for the networking module (overridden by environments)
inputs = {
  # Use naming module outputs
  resource_group_name = dependency.naming.outputs.resource_group
  vnet_name           = dependency.naming.outputs.virtual_network
  
  # Default values (overridden by environments)
  location      = "eastus"
  address_space = ["10.0.0.0/16"]
  subnets       = {}
  dns_servers   = []
  
  # Tags
  tags = {
    ManagedBy   = "Terragrunt"
    Component   = "Networking"
  }
} 