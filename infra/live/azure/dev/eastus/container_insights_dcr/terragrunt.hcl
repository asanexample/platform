# Terragrunt configuration for Container Insights DCR

terraform {
  # Use double-slash notation to ensure relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//container_insights_dcr"
}

# Include common configuration from the root terragrunt.hcl file
include {
  path = find_in_parent_folders()
}

# Get configuration variables using Terragrunt functions
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract environment details
  env         = local.env_vars.locals.environment
  customer    = try(local.common_vars.locals.customer, null)
  prefix      = local.common_vars.locals.prefix
  region_abbv = local.region_vars.locals.region_abbv
  region      = local.region_vars.locals.region
  
  # Common tags
  tags = merge(
    local.common_vars.locals.tags,
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags,
    {
      Component = "Monitoring"
    }
  )
}

# Dependencies
dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation when the dependency is not applied
  mock_outputs = {
    name     = "vip-dev-rg-eus"
    location = "eastus"
  }
}

dependency "log_analytics" {
  config_path = "../log_analytics"

  # Mock outputs for plan and validation
  mock_outputs = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-log-analytics"
    name = "mock-log-analytics"
  }
}

dependency "aks_core" {
  config_path = "../aks_core"

  # Mock outputs for plan and validation
  mock_outputs = {
    id   = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
    name = "mock-aks"
  }
}

# Inputs specific to this module
inputs = {
  # Resource details
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  
  # AKS cluster details
  cluster_name = dependency.aks_core.outputs.name
  cluster_id   = dependency.aks_core.outputs.id
  
  # Log Analytics workspace
  log_analytics_workspace_id = dependency.log_analytics.outputs.id
  
  # Configure data collection settings
  interval                 = "1m"
  namespace_filtering_mode = "Include"
  namespaces               = ["kube-system"]
  enable_container_log_v2  = true
  
  # Data streams to collect
  data_streams = [
    "Microsoft-ContainerLogV2",
    "Microsoft-Perf",
    "Microsoft-KubeEvents",
    "Microsoft-KubePodInventory",
    "Microsoft-KubeNodeInventory",
    "Microsoft-KubeServices"
  ]
  
  # Tags
  tags = local.tags
} 