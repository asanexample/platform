# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR AZURE LOG ANALYTICS
# This is the common component configuration for Azure Log Analytics. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Terraform module source
terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//log_analytics"
}

# ---------------------------------------------------------------------------------------------------------------------
# SHARED VARIABLES
# These variables are used across all environments and regions
# ---------------------------------------------------------------------------------------------------------------------
locals {
  # Extract environment from env.hcl
  environment_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  environment      = local.environment_vars.locals.environment
  
  # Extract region information from region.hcl
  region_vars      = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  region           = local.region_vars.locals.region
  
  # Get common tags from the environment
  common_vars      = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  common_tags      = local.common_vars.locals.tags
}

# Default inputs that typically won't need to be overridden in specific environments
inputs = {
  # Default location from region
  location = local.region
  
  # Default Log Analytics configuration
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = null  # Use Azure default
  
  # Default internet ingestion and query settings
  internet_ingestion_enabled = true
  internet_query_enabled     = true
  
  # Common solution plans across all environments
  solution_plans = [
    {
      solution_name = "ContainerInsights"  # For AKS monitoring
    },
    {
      solution_name = "Security"           # For security monitoring
    }
  ]
  
  # Default tags that should be applied to all Log Analytics workspaces
  tags = merge(local.common_tags, {
    "ResourceType" = "LogAnalyticsWorkspace"
    "Component"    = "Monitoring"
  })
} 