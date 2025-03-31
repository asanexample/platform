# Terragrunt configuration for Azure Log Analytics Workspace in eastus region

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
  customer    = local.customer
  prefix      = local.prefix
  region_abbv = local.region_abbv

  # Resource details
  name                = dependency.naming.outputs.log_analytics_workspace
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  
  # Environment-specific overrides
  sku               = "PerGB2018"  # Standard pricing tier
  retention_in_days = 30           # Data retention period
  
  # Self-diagnostics - Send logs to itself
  diagnostic_settings = [
    {
      name                       = "${dependency.naming.outputs.log_analytics_workspace}-self-diag"
      log_analytics_workspace_id = "self"  # Special value that will be replaced with the workspace's own ID
      enabled_log_categories     = ["Audit"]
      metric_categories          = ["AllMetrics"]
      log_retention_days         = 30
    }
  ]
  
  # Tags
  tags = merge(local.tags, {
    "criticality" = "high"
  })
} 