# Terragrunt configuration for Azure Monitor Workspace (Managed Prometheus) in eastus region

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

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"

  # Mock outputs for plan and validation
  mock_outputs = {
    monitor_workspace = "mock-prometheus"
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

# Terraform configuration for this module
terraform {
  source = "${get_parent_terragrunt_dir()}/infra/modules/azure/monitor_workspace"
}

# Specify inputs for this module
inputs = {
  # Resource details
  name                = dependency.naming.outputs.monitor_workspace != null ? dependency.naming.outputs.monitor_workspace : "${local.prefix}-${local.env}-prometheus-${local.region_abbv}"
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location

  # Tags
  tags = merge(local.tags, {
    "monitoring-type" = "prometheus"
  })
} 