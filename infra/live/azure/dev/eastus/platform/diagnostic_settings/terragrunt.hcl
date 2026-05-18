# Terragrunt configuration for Azure Diagnostic Settings in eastus region
# Routes logs from ACR, Key Vault, and networking resources to Log Analytics

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

include "diag_common" {
  path = find_in_parent_folders("azure/_envcommon/diagnostic_settings.hcl")
}

dependency "log_analytics" {
  config_path = "../log_analytics"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.OperationalInsights/workspaces/mock-law"
  }
}

dependency "container_registry" {
  config_path = "../container_registry"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerRegistry/registries/mockacr"
  }
}

dependency "key_vault" {
  config_path = "../key_vault"
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.KeyVault/vaults/mock-kv"
  }
}

dependency "networking" {
  config_path = "../networking"
  mock_outputs = {
    vnet_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.Network/virtualNetworks/mock-vnet"
  }
}

inputs = {
  create = true

  diagnostic_settings = {
    acr-diagnostics = {
      target_resource_id         = dependency.container_registry.outputs.id
      log_analytics_workspace_id = dependency.log_analytics.outputs.id
      log_category_groups        = ["allLogs"]
      metric_categories          = ["AllMetrics"]
    }
    keyvault-diagnostics = {
      target_resource_id         = dependency.key_vault.outputs.id
      log_analytics_workspace_id = dependency.log_analytics.outputs.id
      log_category_groups        = ["allLogs", "audit"]
      metric_categories          = ["AllMetrics"]
    }
    vnet-diagnostics = {
      target_resource_id         = dependency.networking.outputs.vnet_id
      log_analytics_workspace_id = dependency.log_analytics.outputs.id
      log_category_groups        = ["allLogs"]
      metric_categories          = ["AllMetrics"]
    }
  }
}
