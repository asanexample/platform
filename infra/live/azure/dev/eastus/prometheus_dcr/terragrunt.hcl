# Terragrunt configuration for Prometheus DCR in eastus dev

include "root" {
  path = find_in_parent_folders()
}

locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))

  # Extract commonly used variables
  region      = local.region_vars.locals.region
  tags        = merge(
    local.common_vars.locals.tags,
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name     = "mock-rg"
    location = local.region
  }
}

dependency "monitor_workspace" {
  config_path = "../monitor_workspace"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Monitor/accounts/mock-monitor-workspace"
  }
}


terraform {
  source = "../../../../../modules/azure/prometheus_dcr"
}

inputs = {
  # name and dce_name will use defaults within the module
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  monitor_workspace_id = dependency.monitor_workspace.outputs.id
  tags                = local.tags
} 