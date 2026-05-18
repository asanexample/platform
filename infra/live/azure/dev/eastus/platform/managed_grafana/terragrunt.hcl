# Terragrunt configuration for Azure Managed Grafana in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

dependency "naming" {
  config_path = "../naming"

  mock_outputs = {
    grafana = "mock-grafana"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"

  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "log_analytics" {
  config_path = "../log_analytics"

  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-law"
  }
}

dependency "monitor_workspace" {
  config_path = "../monitor_workspace"

  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Monitor/accounts/mock-monitor-workspace"
  }
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure/managed_grafana"
}

inputs = {
  create = true

  name                = "${include.base.locals.workload}-${include.base.locals.env}-grafana-${include.base.locals.region_abbv}"
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location

  grafana_major_version             = "10"
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true
  zone_redundancy_enabled           = true

  prometheus_workspace_id = dependency.monitor_workspace.outputs.id

  admin_group_object_ids = []
  admin_user_object_ids  = []

  tags = merge(include.base.locals.tags, {
    "monitoring-type" = "grafana"
  })
}
