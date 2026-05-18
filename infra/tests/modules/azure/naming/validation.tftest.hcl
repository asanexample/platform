# Naming Module - Validation Tests
#
# Verifies CAF-aligned naming: {type}-{workload}-{env}-{region}
# For no-hyphen resources: {type}{abbreviated_workload}{env}{region}

# Test basic resource group naming
run "resource_group_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.resource_group == "rg-platform-dev-eus"
    error_message = "Resource group name should be rg-platform-dev-eus"
  }
}

# Test with different workload
run "workload_variation_test" {
  command = plan

  variables {
    workload    = "hipaa"
    environment = "prod"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.resource_group == "rg-hipaa-prod-eus"
    error_message = "Resource group name should be rg-hipaa-prod-eus"
  }

  assert {
    condition     = output.aks_cluster == "aks-hipaa-prod-eus"
    error_message = "AKS cluster name should be aks-hipaa-prod-eus"
  }
}

# Test storage account naming (no hyphens, abbreviated workload)
run "storage_account_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.storage_account == "stplatdeveus"
    error_message = "Storage account should be stplatdeveus (no hyphens, abbreviated workload)"
  }
}

# Test key vault naming (abbreviated workload for 24-char limit)
run "key_vault_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.key_vault == "kv-plat-dev-eus"
    error_message = "Key vault should be kv-plat-dev-eus (abbreviated workload)"
  }
}

# Test AKS cluster naming
run "aks_cluster_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.aks_cluster == "aks-platform-dev-eus"
    error_message = "AKS cluster should be aks-platform-dev-eus"
  }
}

# Test AKS node pool naming (no hyphens, 12 char limit)
run "aks_node_pool_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.aks_node_pool == "npplatdev"
    error_message = "AKS node pool should be npplatdev (no hyphens, abbreviated)"
  }
}

# Test AKS identity naming
run "aks_identity_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.aks_identity == "aksid-platform-dev-eus"
    error_message = "AKS identity should be aksid-platform-dev-eus"
  }
}

# Test virtual network naming
run "virtual_network_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.virtual_network == "vnet-platform-dev-eus"
    error_message = "Virtual network should be vnet-platform-dev-eus"
  }
}

# Test subnet base naming
run "subnet_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.subnet == "snet-platform-dev"
    error_message = "Subnet base should be snet-platform-dev"
  }
}

# Test specialized subnet naming
run "specialized_subnet_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.subnet_node == "snet-platform-dev-node-eus"
    error_message = "Node subnet should be snet-platform-dev-node-eus"
  }

  assert {
    condition     = output.subnet_endpoint == "snet-platform-dev-endpoint-eus"
    error_message = "Endpoint subnet should be snet-platform-dev-endpoint-eus"
  }

  assert {
    condition     = output.subnet_gateway == "snet-platform-dev-gateway-eus"
    error_message = "Gateway subnet should be snet-platform-dev-gateway-eus"
  }
}

# Test network security group naming
run "network_security_group_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.network_security_group == "nsg-platform-dev-eus"
    error_message = "NSG should be nsg-platform-dev-eus"
  }
}

# Test log analytics workspace naming
run "log_analytics_workspace_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.log_analytics_workspace == "law-platform-dev-eus"
    error_message = "Log Analytics should be law-platform-dev-eus"
  }
}

# Test container registry naming (no hyphens)
run "container_registry_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.container_registry == "acrplatdeveus"
    error_message = "Container registry should be acrplatdeveus (no hyphens, abbreviated)"
  }
}

# Test front door naming
run "front_door_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.front_door == "fd-platform-dev-eus"
    error_message = "Front door should be fd-platform-dev-eus"
  }
}

# Test front door endpoint naming
run "frontdoor_endpoint_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.frontdoor_endpoint == "fde-platform-dev-eus"
    error_message = "Front door endpoint should be fde-platform-dev-eus"
  }
}

# Test monitor workspace naming (includes -prometheus suffix)
run "monitor_workspace_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.monitor_workspace == "amw-platform-dev-eus-prometheus"
    error_message = "Monitor workspace should be amw-platform-dev-eus-prometheus"
  }
}

# Test SQL server naming
run "sql_server_naming_test" {
  command = plan

  variables {
    workload    = "data"
    environment = "prod"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.sql_server == "sql-data-prod-eus"
    error_message = "SQL server should be sql-data-prod-eus"
  }
}

# Test cosmos account naming
run "cosmos_account_naming_test" {
  command = plan

  variables {
    workload    = "data"
    environment = "prod"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.cosmos_account == "cosmos-data-prod-eus"
    error_message = "Cosmos account should be cosmos-data-prod-eus"
  }
}

# Test bastion host naming
run "bastion_host_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.bastion_host == "bas-platform-dev-eus"
    error_message = "Bastion host should be bas-platform-dev-eus"
  }
}

# Test private endpoint naming
run "private_endpoint_naming_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.private_endpoint == "pe-platform-dev-eus"
    error_message = "Private endpoint should be pe-platform-dev-eus"
  }
}

# Test workload abbreviation for unknown workload (falls back to first 4 chars)
run "unknown_workload_abbreviation_test" {
  command = plan

  variables {
    workload    = "custom"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.storage_account == "stcustdeveus"
    error_message = "Unknown workload should abbreviate to first 4 chars: stcustdeveus"
  }
}

# Test all environment values work
run "ops_environment_test" {
  command = plan

  variables {
    workload    = "platform"
    environment = "ops"
    region_abbv = "wus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.resource_group == "rg-platform-ops-wus"
    error_message = "Resource group should be rg-platform-ops-wus"
  }

  assert {
    condition     = output.aks_cluster == "aks-platform-ops-wus"
    error_message = "AKS cluster should be aks-platform-ops-wus"
  }
}
