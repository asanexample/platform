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
  
  # Define common naming pattern
  rg_name   = "vip-rg-${local.environment}-${local.region_code}-hosting"
  vnet_name = "vip-vnet-${local.environment}-${local.region_code}-main"
}

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module specified in the terragrunt configuration above
# ---------------------------------------------------------------------------------------------------------------------

# These are common inputs that apply to all hosting deployments
inputs = {
  # Resource group info - these come from the common locals
  resource_group_name = local.rg_name
  location            = local.region
  vnet_name           = local.vnet_name
  
  # Standard storage account settings based on environment
  # Production uses ZRS, non-production uses LRS
  storage_account_tier     = "Standard"
  storage_replication_type = get_env("TF_VAR_environment", "dev") == "prod" ? "ZRS" : "LRS"
  
  # Network security settings
  # Always deny by default and only allow specific subnets
  storage_network_default_action = "Deny"
  storage_network_bypass = ["AzureServices"]
  
  # Public access settings
  # Production disables public access, dev allows it with proper configuration
  storage_allow_public = get_env("TF_VAR_environment", "dev") == "prod" ? false : true
  
  # Default CORS settings for web applications
  # This allows basic web access in development environments
  storage_cors_rules = get_env("TF_VAR_environment", "dev") == "prod" ? [] : [
    {
      allowed_headers    = ["*"]
      allowed_methods    = ["GET", "HEAD", "OPTIONS"]
      allowed_origins    = ["*"]  # Restrict in production
      exposed_headers    = ["Content-Length", "Content-Type"]
      max_age_in_seconds = 3600
    }
  ]
  
  # Storage account configuration 
  storage_name_components = {
    prefix      = "vip"
    environment = local.environment
    region_abbv = local.region_code
    instance    = "001"
  }
  
  # Set permissions to allow access from endpoint subnets
  storage_allowed_subnets = ["az1-endpoint-subnet"]
  
  # Standard containers to create in all regions
  # These containers follow the naming convention in NAMING_CONVENTIONS.md
  storage_containers = {
    "assets" = {
      name                  = "assets"
      container_access_type = "private"
    },
    "public" = {
      name                  = "public"
      container_access_type = get_env("TF_VAR_environment", "dev") == "prod" ? "private" : "blob"
    },
    "pdf" = {
      name                  = "pdf"
      container_access_type = "private"
    }
  }
  
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
} 