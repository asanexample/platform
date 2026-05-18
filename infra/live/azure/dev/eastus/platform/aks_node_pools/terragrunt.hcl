# Terragrunt configuration for Azure AKS Node Pools in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "aks_node_pools_common" {
  path = find_in_parent_folders("azure/_envcommon/aks_node_pools.hcl")
}

dependency "naming" {
  config_path = "../naming"

  mock_outputs = {
    aks_cluster = "mock-aks"
  }
}

dependency "aks_core" {
  config_path = "../aks_core"

  mock_outputs = {
    name                = "mock-aks"
    resource_group_name = "mock-rg"
    id                  = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
  }
}

dependency "aks_identity" {
  config_path = "../aks_identity"
  mock_outputs = {
    id = "/subscriptions/mock-id/resourceGroups/mock-rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/mock-identity"
  }
}

inputs = {
  create = true

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  aks_cluster_id = dependency.aks_core.outputs.id

  app_node_pool = {
    enabled             = true
    name                = "apps"
    vm_size             = "Standard_D8s_v5"
    node_count          = 3
    availability_zones  = ["1", "2", "3"]
    max_pods            = 110
    os_disk_size_gb     = 128
    os_disk_type        = "Managed"
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 5
    mode                = "User"
    node_labels = {
      "nodepool"      = "apps"
      "app"           = "true"
      "workload"      = "general"
      "node-priority" = "regular"
    }
    node_taints = []
  }

  app_node_pool_min_count     = 3
  temporary_name_for_rotation = "tempapps"

  standard_node_pool = {
    availability_zones = ["1", "2", "3"]
    node_count         = 3
    min_count          = 3
  }

  tags = merge(include.base.locals.tags, {
    "network-cilium-managed-by" = "cilium"
    "cilium-version"            = "1.17.2"
  })
}
