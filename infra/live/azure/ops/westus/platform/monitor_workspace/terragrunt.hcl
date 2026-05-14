# Terragrunt configuration for Azure Monitor Workspace in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "naming" {
  config_path = "../naming"
  mock_outputs = {
    monitor_workspace = "mock-amw-prometheus"
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure/monitor_workspace"
}

inputs = {
  create = true

  name                = dependency.naming.outputs.monitor_workspace
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location
  tags                = include.base.locals.tags
}
