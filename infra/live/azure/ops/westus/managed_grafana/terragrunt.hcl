# Terragrunt configuration for Azure Managed Grafana in westus region for ops environment

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
    grafana = "mock-grafana"
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

dependency "log_analytics" {
  config_path = "../log_analytics"

  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-law"
  }
}

# Terraform configuration for this module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/managed_grafana"
}

# Specify inputs for this module
inputs = {
  # Resource details
  name                = "${local.prefix}-${local.env}-grafana-${local.region_abbv}"
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  
  # Grafana configuration
  grafana_major_version             = "10" # Latest supported version
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true
  zone_redundancy_enabled           = true
  
  # Azure AD admin groups - replace with actual Azure AD group IDs in production
  admin_group_object_ids = []
  
  # Azure AD admin users - replace with actual Azure AD user IDs as needed
  admin_user_object_ids = []
  
  # Tags
  tags = merge(local.tags, {
    "monitoring-type" = "grafana"
    "environment"     = local.env
  })
} 