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
    "eastus2" = "eus2"
    "westus2" = "wus2"
    "centralus" = "cus"
    "westus3" = "wus3"
    "northeurope" = "neu"
    "westeurope" = "weu"
    "uksouth" = "uks"
  }
  
  # Get the region code for current region
  region_code = local.region_code_map[local.region]
  
  # Define common naming pattern
  vnet_name = "vip-vnet-${local.environment}-${local.region_code}-main"
  rg_name   = "vip-rg-${local.environment}-${local.region_code}-net"
  
  # Azure CIDR allocations per region according to allocations.csv
  # IMPORTANT: These are reference values only and should be overridden in each regional configuration
  # with the correct values from allocations.csv
  azure_cidr_map = {
    "eastus"      = "10.101.0.0/21"
    "eastus2"     = "10.101.8.0/21"
    "centralus"   = "10.101.16.0/21"
    "westus"      = "10.101.24.0/21"
    "westus2"     = "10.101.32.0/21"
    "westus3"     = "10.101.40.0/21"
    "canadacentral" = "10.101.48.0/21"
    "brazilsouth" = "10.101.56.0/21"
    "westeurope"  = "10.101.64.0/21"
    "northeurope" = "10.101.72.0/21"
    "uksouth"     = "10.101.80.0/21"
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
  
  # DO NOT USE this default address space in production. Override with the proper regional CIDR
  # from the azure_cidr_map above for the specific region you're deploying to
  address_space       = ["10.1.0.0/16"]  # EXAMPLE ONLY - Override in regional configuration
  
  # Sample subnet config - should be replaced with proper subnets based on allocations.csv
  subnets             = {}
  
  dns_servers         = []
  tags                = local.common_tags
} 