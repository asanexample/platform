# Terragrunt configuration for Azure networking in westus region

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
  source = "${get_repo_root()}/infra/modules/azure/networking"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    virtual_network = "mock-vnet"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
    location = "westus"
  }
}

# Specify inputs specific to this module
inputs = {
  # Resource group
  resource_group_name = dependency.resource_group.outputs.name
  location = dependency.resource_group.outputs.location
  
  # VNet configuration
  vnet_name = dependency.naming.outputs.virtual_network
  address_space = ["10.9.0.0/16"]  # West US Dev
  
  # Subnets
  subnets = {
    # AZ1 subnets
    "az1-node-subnet" = {
      address_prefixes = ["10.9.0.0/20"]
    }
    "az1-pod-subnet" = {
      address_prefixes = ["10.9.16.0/20"]
    }
    "az1-endpoint-subnet" = {
      address_prefixes = ["10.9.32.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    
    # AZ2 subnets
    "az2-node-subnet" = {
      address_prefixes = ["10.9.64.0/20"]
    }
    "az2-pod-subnet" = {
      address_prefixes = ["10.9.80.0/20"]
    }
    "az2-endpoint-subnet" = {
      address_prefixes = ["10.9.96.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    
    # AZ3 subnets
    "az3-node-subnet" = {
      address_prefixes = ["10.9.128.0/20"]
    }
    "az3-pod-subnet" = {
      address_prefixes = ["10.9.144.0/20"]
    }
    "az3-endpoint-subnet" = {
      address_prefixes = ["10.9.160.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    
    # Shared subnets
    "gateway-subnet" = {
      address_prefixes = ["10.9.192.0/24"]
    }
    "bastion-subnet" = {
      address_prefixes = ["10.9.193.0/24"]
    }
  }
  
  # Tags
  tags = local.tags
} 