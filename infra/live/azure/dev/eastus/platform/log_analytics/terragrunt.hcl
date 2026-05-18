# Terragrunt configuration for Azure Log Analytics Workspace in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "log_analytics_common" {
  path = find_in_parent_folders("azure/_envcommon/log_analytics.hcl")
}

dependency "naming" {
  config_path = "../naming"

  mock_outputs = {
    log_analytics_workspace = "mock-law"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

inputs = {
  create = true

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  name                = dependency.naming.outputs.log_analytics_workspace
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location

  sku               = "PerGB2018"
  retention_in_days = 30

  diagnostic_settings = [
    {
      name                       = "${dependency.naming.outputs.log_analytics_workspace}-self-diag"
      log_analytics_workspace_id = "self"
      enabled_log_categories     = ["Audit"]
      metric_categories          = ["AllMetrics"]
      log_retention_days         = 30
    }
  ]

  tags = merge(include.base.locals.tags, {
    "criticality" = "high"
  })
}
