# Terragrunt configuration for Azure Log Analytics Workspace in westus region (ops environment)

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Merge all variables for convenience
  all_vars = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.common_vars.locals
  )
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for Log Analytics
include "log_analytics_common" {
  path = find_in_parent_folders("azure/_envcommon/log_analytics.hcl")
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"

  # Mock outputs for plan and validation
  mock_outputs = {
    log_analytics_workspace = "mock-law"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  # Mock outputs for plan and validation
  mock_outputs = {
    name     = "mock-rg"
    location = local.region
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # Environment variables
  environment = local.env
  prefix      = local.prefix
  region_abbv = local.region_abbv

  # Resource details
  name                = dependency.naming.outputs.log_analytics_workspace
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  
  # Environment-specific overrides - use higher retention for ops environment
  sku               = "PerGB2018"
  retention_in_days = 60         # Increase retention for ops environment
  daily_quota_gb    = 5          # Set a daily quota limit of 5GB for the workspace
  
  # RBAC role assignments for accessing the Log Analytics workspace
  role_assignments = [
    {
      principal_id         = "403dc11a-5399-4f10-9515-91f048eea58a"  # Current user
      role_definition_name = "Log Analytics Contributor"
      description          = "Grants access to view and modify Log Analytics workspace"
    }
  ]
  
  # Self-diagnostics are already set up in Azure and will be managed outside of Terraform
  
  # Tags
  tags = merge(local.tags, {
    "criticality" = "high"
    "environment" = "ops"
  })
} 