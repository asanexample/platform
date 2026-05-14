# Terragrunt configuration for Azure Managed Grafana in westus region for ops environment

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
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

# Terraform configuration for this module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/managed_grafana"
}

# Specify inputs for this module
inputs = {
  create = true

  # Resource details
  name                = "${include.base.locals.workload}-${include.base.locals.env}-grafana-${include.base.locals.region_abbv}"
  resource_group_name = dependency.resource_group.outputs.name
  location            = dependency.resource_group.outputs.location

  # Grafana configuration
  grafana_major_version             = "10" # Latest supported version
  api_key_enabled                   = true
  deterministic_outbound_ip_enabled = true
  public_network_access_enabled     = true
  zone_redundancy_enabled           = false # Disabled for westus as it's not supported

  prometheus_workspace_id = dependency.monitor_workspace.outputs.id

  admin_group_object_ids = []

  # Azure AD admin users - replace with actual Azure AD user IDs as needed
  admin_user_object_ids = []

  # Tags
  tags = merge(include.base.locals.tags, {
    "monitoring-type" = "grafana"
    "environment"     = include.base.locals.env
  })
}
