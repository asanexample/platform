# Terragrunt configuration for Azure Log Analytics in eastus region

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

  # Control for linked storage accounts - set to false if you want to avoid creating them
  # This is useful when importing existing resources or if you're encountering duplicate resource errors
  create_linked_storage = false
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

# Add dependency on storage account
dependency "storage" {
  config_path = "../storage"

  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Storage/storageAccounts/mocksa"
  }
}

# Terraform configuration source
terraform {
  source = "${get_parent_terragrunt_dir()}/modules/azure/log_analytics"
}

# Module inputs
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
  
  # Log Analytics configuration
  sku                 = "PerGB2018"  # Standard pricing tier
  retention_in_days   = 30           # Data retention period
  
  # Solution packs to install - Removed ContainerInsights to avoid conflicts with DCR approach
  solution_plans = [
    {
      solution_name = "Security"
    },
    {
      solution_name = "AzureActivity"
    }
  ]
  
  # Enable diagnostic settings for the Log Analytics workspace itself
  diagnostic_settings = [{
    name                       = "${dependency.naming.outputs.log_analytics_workspace}-self-diag"
    log_analytics_workspace_id = "self"  # Send logs to itself
    enabled_log_categories     = ["Audit"]
    metric_categories          = ["AllMetrics"]
    log_retention_days         = 30
  }]
  
  # Link storage account for long-term retention of different log types
  linked_storage_accounts = {}
  
  # Tags
  tags = merge(local.tags, {
    "component"    = "monitoring"
    "criticality"  = "high"
  })
}
