# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AZURE NETWORKING
# This is the common component configuration for Azure networking. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Terraform module source for networking
terraform {
  source = "${get_repo_root()}/infra/modules/azure//networking"
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED VARIABLES AND GLOBAL NETWORK ARCHITECTURE
# These variables establish the baseline networking configuration across all environments
# ---------------------------------------------------------------------------------------------------------------------
locals {
  # Extract environment from env.hcl
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  
  # Extract region information from region.hcl
  region_vars    = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region         = local.region_vars.locals.region
  
  # Map of Azure regions to region codes for resource naming
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
  
  # Get the region code for current region
  region_code = lookup(local.region_code_map, local.region, "unknown")
  
  # Global CIDR Allocation Strategy
  # For complete documentation, see: infra/docs/06-cidr-allocation.md
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
  
  # Get common tags from the environment
  common_vars    = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  common_tags    = local.common_vars.locals.tags
}

# ---------------------------------------------------------------------------------------------------------------------
# COMMON NETWORK CONFIGURATION DEFAULTS
# These settings create baseline configurations that can be overridden by environment-specific values
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # The name and resource group will typically come from other modules in environment-specific configs
  
  # Default network settings
  address_space         = [local.azure_cidr_map[local.region]]
  dns_servers           = null
  
  # Default subnet configuration - will typically be overridden in environment-specific config
  subnets               = {}
  
  # AKS-specific networking defaults
  enable_aks_networking        = false
  aks_subnet_name             = null
  aks_cluster_name            = null
  aks_private_cluster_enabled = true
  aks_node_resource_group     = null
  
  # Default tags
  tags = merge(local.common_tags, {
    "ResourceType" = "Networking"
  })
} 