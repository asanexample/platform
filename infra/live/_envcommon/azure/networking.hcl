# Common Terragrunt configuration for Azure networking across all regions

# Specify the terraform module source
terraform {
  source = "${dirname(find_in_parent_folders())}/modules/azure/networking"
}

# Common locals that can be used across all regions
locals {
  # Extract environment and region
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region           = local.region_vars.locals.region
  
  # Map of Azure region to region code for resource naming
  region_code_map = {
    "eastus" = "eus"
    "westus" = "wus"
  }
  
  # Get the region code for current region
  region_code = local.region_code_map[local.region]
  
  # Define common naming pattern
  vnet_name = "vip-vnet-${local.environment}-${local.region_code}-main"
  rg_name   = "vip-rg-${local.environment}-${local.region_code}-net"
  
  # Common network configuration that applies to all regions
  common_subnet_config = {
    "app-subnet" = {
      address_prefixes  = ["10.1.1.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault"]
    }
    "data-subnet" = {
      address_prefixes  = ["10.1.2.0/24"]
      service_endpoints = ["Microsoft.Storage", "Microsoft.Sql"]
    }
    "mgmt-subnet" = {
      address_prefixes  = ["10.1.3.0/24"]
      service_endpoints = []
    }
  }
  
  # Common tags for all resources
  common_tags = {
    Environment        = local.environment
    Region             = local.region
    Component          = "Networking"
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    AutoShutdown       = "True"
    DataClassification = "Internal"
  }
}

# Default inputs that can be overridden by region-specific configurations
inputs = {
  resource_group_name = local.rg_name
  location            = local.region
  vnet_name           = local.vnet_name
  
  address_space       = ["10.1.0.0/16"]
  subnets             = local.common_subnet_config
  dns_servers         = []
  tags                = local.common_tags
} 