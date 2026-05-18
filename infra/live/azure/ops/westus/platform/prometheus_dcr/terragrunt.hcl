# Terragrunt configuration for Prometheus DCR in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "monitor_workspace" {
  config_path = "../monitor_workspace"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Monitor/accounts/mock-monitor-workspace"
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure/prometheus_dcr"
}

inputs = {
  create = true

  resource_group_name  = dependency.resource_group.outputs.name
  location             = dependency.resource_group.outputs.location
  monitor_workspace_id = dependency.monitor_workspace.outputs.id
  tags                 = include.base.locals.tags
}
