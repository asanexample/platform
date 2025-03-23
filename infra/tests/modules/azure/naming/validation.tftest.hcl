/**
 * # Naming Module - Validation Test
 * 
 * This test verifies validation conditions for the naming module.
 */

# Test valid prefix
run "prefix_validation_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.resource_group == "abc-test-dev-rg-eu"
    error_message = "Resource group name should match expected format"
  }
}

# Test valid customer name
run "customer_name_validation_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "centric"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.resource_group == "abc-centric-dev-rg-eu"
    error_message = "Resource group with valid customer name should match expected format"
  }
}

# Test valid environment
run "environment_validation_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "prod"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.resource_group == "abc-test-prod-rg-eu"
    error_message = "Resource group with valid environment should match expected format"
  }
}

# Test valid region abbreviation
run "region_abbv_validation_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eus"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = output.resource_group == "abc-test-dev-rg-eus"
    error_message = "Resource group with valid region abbreviation should match expected format"
  }
}

# Test resource group naming
run "resource_group_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-rg-eu$", output.resource_group))
    error_message = "Resource group name should match expected format"
  }
}

# Test storage account naming - should be lowercase, no hyphens
run "storage_account_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abctestdevsaeu$", output.storage_account))
    error_message = "Storage account name should match expected format (lowercase, no hyphens)"
  }
}

# Test AKS cluster naming
run "aks_cluster_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-aks-eu$", output.aks_cluster))
    error_message = "AKS cluster name should match expected format"
  }
}

# Test AKS identity naming
run "aks_identity_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-aksid-eu$", output.aks_identity))
    error_message = "AKS identity name should match expected format"
  }
}

# Test workload identity naming
run "workload_identity_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-workid-eu$", output.workload_identity))
    error_message = "Workload identity name should match expected format"
  }
}

# ============================================================================
# Network Resources Tests
# ============================================================================

# Test virtual network naming
run "virtual_network_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-vnet-eu$", output.virtual_network))
    error_message = "Virtual network name should match expected format (omitting customer)"
  }
}

# Test subnet naming pattern
run "subnet_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet$", output.subnet))
    error_message = "Subnet name base should match expected format (omitting customer)"
  }
}

# Test specialized subnet naming
run "specialized_subnet_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet-node-eu$", output.subnet_node))
    error_message = "Node subnet name should match expected format (omitting customer)"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet-api-eu$", output.subnet_api))
    error_message = "API subnet name should match expected format (omitting customer)"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet-app-eu$", output.subnet_app))
    error_message = "App subnet name should match expected format (omitting customer)"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet-db-eu$", output.subnet_db))
    error_message = "Database subnet name should match expected format (omitting customer)"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet-endpoint-eu$", output.subnet_endpoint))
    error_message = "Endpoint subnet name should match expected format (omitting customer)"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet-service-eu$", output.subnet_service))
    error_message = "Service subnet name should match expected format (omitting customer)"
  }

  assert {
    condition     = can(regex("^abc-dev-subnet-gateway-eu$", output.subnet_gateway))
    error_message = "Gateway subnet name should match expected format (omitting customer)"
  }
}

# Test network security group naming
run "network_security_group_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-nsg-eu$", output.network_security_group))
    error_message = "Network security group name should match expected format (omitting customer)"
  }
}

# Test route table naming
run "route_table_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-rt-eu$", output.route_table))
    error_message = "Route table name should match expected format (omitting customer)"
  }
}

# Test load balancer naming
run "load_balancer_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-lb-eu$", output.load_balancer))
    error_message = "Load balancer name should match expected format (omitting customer)"
  }
}

# Test public IP naming
run "public_ip_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test" 
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-pip-eu$", output.public_ip))
    error_message = "Public IP name should match expected format (omitting customer)"
  }
}

# ============================================================================
# Database Resources Tests
# ============================================================================

# Test SQL server naming
run "sql_server_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-sql-eu$", output.sql_server))
    error_message = "SQL server name should match expected format"
  }
}

# Test SQL database naming
run "sql_database_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-sqldb-eu$", output.sql_database))
    error_message = "SQL database name should match expected format"
  }
}

# Test Cosmos DB account naming
run "cosmos_account_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-cosmos-eu$", output.cosmos_account))
    error_message = "Cosmos DB account name should match expected format"
  }
}

# ============================================================================
# App Services Resources Tests
# ============================================================================

# Test App Service naming
run "app_service_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-app-eu$", output.app_service))
    error_message = "App Service name should match expected format"
  }
}

# Test Function App naming
run "function_app_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-func-eu$", output.function_app))
    error_message = "Function App name should match expected format"
  }
}

# Test App Configuration naming
run "app_configuration_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-appconf-eu$", output.app_configuration))
    error_message = "App Configuration name should match expected format"
  }
}

# ============================================================================
# Security Resources Tests
# ============================================================================

# Test Key Vault naming
run "key_vault_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-kv-eu$", output.key_vault))
    error_message = "Key Vault name should match expected format"
  }
}

# Test Private Endpoint naming
run "private_endpoint_naming_test" {
  command = plan

  variables {
    prefix      = "abc" 
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-pe-eu$", output.private_endpoint))
    error_message = "Private Endpoint name should match expected format"
  }
}

# ============================================================================
# Monitoring Resources Tests
# ============================================================================

# Test Log Analytics Workspace naming
run "log_analytics_workspace_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-law-eu$", output.log_analytics_workspace))
    error_message = "Log Analytics Workspace name should match expected format (omitting customer)"
  }
}

# Test Application Insights naming
run "application_insights_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-ai-eu$", output.application_insights))
    error_message = "Application Insights name should match expected format"
  }
}

# Test Monitor Workspace naming
run "monitor_workspace_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-amw-eu-prometheus$", output.monitor_workspace))
    error_message = "Monitor Workspace name should match expected format including prometheus suffix"
  }
}

# Test Managed Prometheus naming
run "managed_prometheus_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-prom-eu$", output.managed_prometheus))
    error_message = "Managed Prometheus name should match expected format (omitting customer)"
  }
}

# Test Container Insights naming
run "container_insights_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-ci-eu$", output.container_insights))
    error_message = "Container Insights name should match expected format (omitting customer)"
  }
}

# ============================================================================
# Integration Resources Tests
# ============================================================================

# Test Event Hub Namespace naming
run "event_hub_namespace_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-ehns-eu$", output.event_hub_namespace))
    error_message = "Event Hub Namespace name should match expected format"
  }
}

# Test Event Hub naming
run "event_hub_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-eh-eu$", output.event_hub))
    error_message = "Event Hub name should match expected format"
  }
}

# ============================================================================
# Container Resources Tests
# ============================================================================

# Test Container Registry naming
run "container_registry_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  # Container Registry names cannot contain hyphens and must be lowercase
  assert {
    condition     = can(regex("^abctestdevacreu$", output.container_registry))
    error_message = "Container Registry name should match expected format (lowercase, no hyphens)"
  }
}

# Test AKS Node Pool naming
run "aks_node_pool_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abcdevnp$", output.aks_node_pool))
    error_message = "AKS Node Pool name should match expected format (no hyphens, truncated)"
  }
}

# ============================================================================
# Edge Networking Resources Tests
# ============================================================================

# Test Front Door naming
run "front_door_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-fd-eu$", output.front_door))
    error_message = "Front Door name should match expected format (omitting customer)"
  }
}

# Test Front Door Endpoint naming
run "frontdoor_endpoint_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-test-dev-fd-endpoint-eu$", output.frontdoor_endpoint))
    error_message = "Front Door Endpoint name should match expected format"
  }
}

# Test Bastion Host naming
run "bastion_host_naming_test" {
  command = plan

  variables {
    prefix      = "abc"
    customer    = "test"
    environment = "dev"
    region_abbv = "eu"
  }

  module {
    source = "../../../../modules/azure/naming"
  }

  assert {
    condition     = can(regex("^abc-dev-bastion-eu$", output.bastion_host))
    error_message = "Bastion Host name should match expected format (omitting customer)"
  }
} 