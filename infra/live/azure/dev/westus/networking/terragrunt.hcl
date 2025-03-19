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
    aks_cluster = "mock-aks"
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
  address_space = ["10.101.24.0/21"]  # Westus region CIDR per allocations.csv
  
  # Subnets following allocations.csv
  subnets = {
    # AZ1 (westus-1) subnets
    "az1-kubernetes" = {
      address_prefixes  = ["10.101.24.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az1-services" = {
      address_prefixes  = ["10.101.24.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az1-endpoints" = {
      address_prefixes  = ["10.101.24.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az1-transit" = {
      address_prefixes  = ["10.101.24.112/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ2 (westus-2) subnets
    "az2-kubernetes" = {
      address_prefixes  = ["10.101.25.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az2-services" = {
      address_prefixes  = ["10.101.25.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az2-endpoints" = {
      address_prefixes  = ["10.101.25.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az2-transit" = {
      address_prefixes  = ["10.101.25.112/29"]
      service_endpoints = ["Microsoft.Storage"]
    },
    
    # AZ3 (westus-3) subnets
    "az3-kubernetes" = {
      address_prefixes  = ["10.101.26.0/26"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
    },
    "az3-services" = {
      address_prefixes  = ["10.101.26.64/27"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
    },
    "az3-endpoints" = {
      address_prefixes  = ["10.101.26.96/28"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
    },
    "az3-transit" = {
      address_prefixes  = ["10.101.26.112/29"]
      service_endpoints = ["Microsoft.Storage"]
    }
  }
  
  # AKS Networking Configuration - updated to use the appropriate kubernetes subnet
  enable_aks_networking = true
  aks_subnet_name = "az1-kubernetes"
  aks_cluster_name = dependency.naming.outputs.aks_cluster
  aks_private_cluster_enabled = true
  aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
  
  # Tags
  tags = local.tags
} 