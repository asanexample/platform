# Terragrunt configuration for Azure Monitor Alerts in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

include "alerts_common" {
  path = find_in_parent_folders("azure/_envcommon/monitor_alerts.hcl")
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    name     = "mock-rg"
    location = include.base.locals.region
  }
}

dependency "aks_core" {
  config_path = "../aks_core"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
  }
}

inputs = {
  create = true

  resource_group_name = dependency.resource_group.outputs.name
  workload            = include.base.locals.workload
  environment         = include.base.locals.env
  region_abbv         = include.base.locals.region_abbv

  metric_alerts = {
    aks-cpu-high = {
      description       = "AKS cluster CPU usage exceeds 80%"
      severity          = 2
      scopes            = [dependency.aks_core.outputs.id]
      frequency         = "PT5M"
      window_size       = "PT15M"
      action_group_keys = ["platform-warning"]
      criteria = [{
        metric_namespace = "Microsoft.ContainerService/managedClusters"
        metric_name      = "node_cpu_usage_percentage"
        aggregation      = "Average"
        operator         = "GreaterThan"
        threshold        = 80
      }]
    }
    aks-memory-high = {
      description       = "AKS cluster memory usage exceeds 80%"
      severity          = 2
      scopes            = [dependency.aks_core.outputs.id]
      frequency         = "PT5M"
      window_size       = "PT15M"
      action_group_keys = ["platform-warning"]
      criteria = [{
        metric_namespace = "Microsoft.ContainerService/managedClusters"
        metric_name      = "node_memory_working_set_percentage"
        aggregation      = "Average"
        operator         = "GreaterThan"
        threshold        = 80
      }]
    }
    aks-node-not-ready = {
      description       = "AKS cluster has nodes in NotReady state"
      severity          = 1
      scopes            = [dependency.aks_core.outputs.id]
      frequency         = "PT1M"
      window_size       = "PT5M"
      action_group_keys = ["platform-critical"]
      criteria = [{
        metric_namespace = "Microsoft.ContainerService/managedClusters"
        metric_name      = "kube_node_status_condition"
        aggregation      = "Total"
        operator         = "GreaterThan"
        threshold        = 0
        dimension = [{
          name     = "status2"
          operator = "Include"
          values   = ["NotReady"]
        }]
      }]
    }
    aks-pod-failed = {
      description       = "AKS cluster has pods in Failed state"
      severity          = 2
      scopes            = [dependency.aks_core.outputs.id]
      frequency         = "PT5M"
      window_size       = "PT15M"
      action_group_keys = ["platform-warning"]
      criteria = [{
        metric_namespace = "Microsoft.ContainerService/managedClusters"
        metric_name      = "kube_pod_status_phase"
        aggregation      = "Total"
        operator         = "GreaterThan"
        threshold        = 0
        dimension = [{
          name     = "phase"
          operator = "Include"
          values   = ["Failed"]
        }]
      }]
    }
  }

  tags = merge(include.base.locals.tags, {
    "monitoring-scope" = "platform-alerts"
  })
}
