# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AZURE HOSTING
# This is the common component configuration for Azure hosting infrastructure across all environments and regions.
# ---------------------------------------------------------------------------------------------------------------------

# Do not include root here - it's handled by the region-specific files
# include "root" {
#   path = find_in_parent_folders()
# }

# Specify the terraform module source
terraform {
  # Use double-slash to ensure the path is treated as absolute within the repo
  source = "${dirname(find_in_parent_folders())}//modules/azure/hosting"
}

# ---------------------------------------------------------------------------------------------------------------------
# COMMON LOCALS
# These locals are used in all regions for naming consistency and common configurations
# ---------------------------------------------------------------------------------------------------------------------
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
    "northeurope" = "neu"
    "westeurope" = "weu"
    "southeastasia" = "sea"
    "eastasia" = "eas"
    # Add more regions as needed
  }
  
  # Get the region code for current region
  region_code = local.region_code_map[local.region]
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module specified in the terragrunt configuration above
# ---------------------------------------------------------------------------------------------------------------------

# These are common inputs that apply to all hosting deployments
inputs = {
  # Naming module parameters
  prefix      = "vip"
  stage       = local.environment
  region_abbv = local.region_code
  customer    = null  # Set to appropriate customer name for customer-specific resources
  
  # Location parameter
  location = local.region

  # Network security settings
  # Always deny by default and only allow specific subnets
  storage_network_default_action = "Deny"
  storage_network_bypass = ["AzureServices"]
  
  # Set permissions to allow access from endpoint subnets
  storage_allowed_subnets = ["endpoint"]
  
  # Common tags for all hosting instances
  tags = {
    Environment        = local.environment
    Region             = local.region
    Component          = "Hosting"
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
  }
  
  # Note: Network configuration (CIDR blocks and subnet configurations) is now defined
  # in each region's network.hcl file and read by the terragrunt.hcl file.
  # Storage configuration is now in storage.hcl and included directly in terragrunt.hcl
} 