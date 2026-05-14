# Terragrunt configuration for Azure Log Analytics in eastus region

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars      = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars   = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars  = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  workload_vars = read_terragrunt_config(find_in_parent_folders("workload.hcl"))
  common_vars   = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Merge all variables for convenience
  all_vars = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
    local.common_vars.locals
  )
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  workload    = local.workload_vars.locals.workload
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags,
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags,
    local.workload_vars.locals.workload_tags,
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

# Terraform configuration source - use relative path
terraform {
  source = "../../../../../modules/azure/log_analytics"
}

# Provider configuration
generate "provider" {
  path      = "provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}
}
EOF
}

# Module inputs
inputs = {
  # Environment variables
  environment = local.env
  workload    = local.workload
  region_abbv = local.region_abbv

  # Resource details
  name                = dependency.naming.outputs.log_analytics_workspace
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  
  # Log Analytics configuration
  sku                 = "PerGB2018"  # Standard pricing tier
  retention_in_days   = 30           # Data retention period
  
  # Solution packs to install
  solution_plans = [
    {
      solution_name = "ContainerInsights"  # For AKS monitoring
    },
    {
      solution_name = "Security"           # For security monitoring
    },
    {
      solution_name = "AzureActivity"      # For Azure Activity logs
    }
  ]
  
  # Diagnostics settings for the workspace itself
  diagnostic_settings = [
    {
      name                       = "${dependency.naming.outputs.log_analytics_workspace}-diag"
      log_analytics_workspace_id = "self"  # Send logs to itself
      
      enabled_log_categories = [
        "Audit"
      ]
      
      metric_categories = [
        "AllMetrics"
      ]
      
      log_retention_days = 30
    }
  ]
  
  # Tags
  tags = merge(local.tags, {
    "component"    = "monitoring"
    "criticality"  = "high"
  })
} 