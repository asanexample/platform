# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR RESOURCE NAMING
# This file defines the configuration for the Azure naming module that standardizes resource naming
# across all environments and regions.
# ---------------------------------------------------------------------------------------------------------------------

terraform {
  source = "${dirname(find_in_parent_folders())}/modules/azure/naming"
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED LOCALS FROM PARENT FILES
# These locals are automatically pulled from environment and region configuration files.
# ---------------------------------------------------------------------------------------------------------------------
locals {
  # Extract environment from env.hcl
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  
  # Extract region information from region.hcl
  region_vars    = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region         = local.region_vars.locals.region
  
  # Map Azure regions to their standard abbreviations
  region_code_map = {
    "eastus"      = "eus"
    "eastus2"     = "eus2"
    "westus"      = "wus"
    "westus2"     = "wus2" 
    "centralus"   = "cus"
    "northeurope" = "neu"
    "westeurope"  = "weu"
    "southeastasia" = "sea"
    "eastasia"    = "eas"
    "uksouth"     = "uks"
    "ukwest"      = "ukw"
    "francecentral" = "frc"
  }
  
  # Get the region code for the current region
  region_code = lookup(local.region_code_map, local.region, "unknown")
  
  # Optional: extract customer information if available
  # This is useful when deploying customer-specific resources
  customer_vars = read_terragrunt_config(find_in_parent_folders("customer.hcl"), { locals = { customer = null } })
  customer      = lookup(local.customer_vars.locals, "customer", null)
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we need to pass to the module to build standardized resource names.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  prefix      = "vip"
  customer    = local.customer
  stage       = local.environment
  region_abbv = local.region_code
} 