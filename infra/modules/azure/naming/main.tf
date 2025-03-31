/**
 * # Azure Resource Naming Module
 *
 * This module provides standardized naming functions for Azure resources based on
 * Azure's naming restrictions and VIP Platform conventions.
 *
 * The module helps ensure consistency across all resources and compliance with
 * Azure-specific naming requirements.
 */

locals {
  # Default prefix for all resources (can be overridden)
  default_prefix = var.prefix != null ? var.prefix : "vip"

  # Clean the customer name to ensure it's valid for all resource types
  # Removes special characters and converts to lowercase
  normalized_customer = var.customer != null ? lower(replace(var.customer, "/[^a-zA-Z0-9]/", "")) : ""

  # Region abbreviation mapping (if needed for consistency)
  region_abbv = var.region_abbv

  # Resource type abbreviations
  resource_types = {
    resource_group           = "rg"
    storage_account          = "sa"
    key_vault                = "kv"
    aks_cluster              = "aks"
    workload_identity        = "workid"
    federated_identity       = "fedcred"
    log_analytics_workspace  = "law"
    app_service              = "app"
    function_app             = "func"
    event_hub_namespace      = "ehns"
    event_hub                = "eh"
    service_bus_namespace    = "sbns"
    service_bus_queue        = "sbq"
    service_bus_topic        = "sbt"
    virtual_network          = "vnet"
    subnet                   = "subnet"
    network_security_group   = "nsg"
    application_gateway      = "agw"
    front_door               = "fd"
    frontdoor_profile        = "fd"
    frontdoor_endpoint       = "fd-endpoint"
    frontdoor_origin_group   = "fd-og"
    frontdoor_origin         = "fd-origin"
    frontdoor_route          = "fd-route"
    user_assigned_identity   = "id"
    container_registry       = "acr"
    storage_account_endpoint = "sape"
    virtual_machine          = "vm"
    app_configuration        = "appconf"
    sql_server               = "sql"
    sql_database             = "sqldb"
    cosmos_account           = "cosmos"
    monitor_workspace        = "amw"
    application_insights     = "ai"
    bastion_host             = "bastion"
    route_table              = "rt"
    private_endpoint         = "pe"
    private_dns_zone         = "pdns"
    public_ip                = "pip"
    load_balancer            = "lb"
    aks_node_pool            = "np"
    managed_prometheus       = "prom"
    container_insights       = "ci"
    aks_identity             = "aksid"
  }

  # Azure resource naming restrictions
  naming_rules = {
    resource_group = {
      max_length  = 90
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    storage_account = {
      max_length  = 24
      valid_chars = "^[a-z0-9]+$"
      no_hyphens  = true
    }
    key_vault = {
      max_length  = 24
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    aks_cluster = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    workload_identity = {
      max_length  = 128
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    federated_identity = {
      max_length  = 128
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    log_analytics_workspace = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    function_app = {
      max_length  = 60
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    event_hub_namespace = {
      max_length  = 50
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    event_hub = {
      max_length  = 50
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    virtual_network = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    subnet = {
      max_length  = 80
      valid_chars = "^[a-zA-Z0-9\\-_\\.]+$"
    }
    front_door = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    frontdoor_profile = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    frontdoor_endpoint = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    frontdoor_origin_group = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    frontdoor_origin = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    frontdoor_route = {
      max_length  = 64
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    container_registry = {
      max_length  = 50
      valid_chars = "^[a-zA-Z0-9]+$"
      no_hyphens  = true
    }
    app_configuration = {
      max_length  = 50
      valid_chars = "^[a-zA-Z0-9\\-]+$"
    }
    cosmos_account = {
      max_length  = 44
      valid_chars = "^[a-z0-9\\-]+$"
    }
    sql_server = {
      max_length  = 63
      valid_chars = "^[a-z0-9\\-]+$"
    }
    sql_database = {
      max_length  = 128
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    private_dns_zone = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-\\.]+$"
    }
    aks_node_pool = {
      max_length  = 12
      valid_chars = "^[a-z0-9]+$"
      no_hyphens  = true
    }
    managed_prometheus = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    container_insights = {
      max_length  = 63
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    aks_identity = {
      max_length  = 128
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
  }

  # Generate standard resource names using consistent format
  customer_part = var.customer != null ? "-${var.customer}" : ""

  names = {
    # Resource Group
    resource_group = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.resource_group}-${local.region_abbv}",

    # Storage Account (special format with no hyphens, 24 char limit)
    storage_account = "${local.default_prefix}${local.normalized_customer}${var.environment}${local.resource_types.storage_account}${local.region_abbv}",

    # Key Vault 
    key_vault = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.key_vault}-${local.region_abbv}",

    # AKS Cluster
    aks_cluster = "${local.default_prefix}-${var.environment}-${local.resource_types.aks_cluster}-${local.region_abbv}",

    # Workload Identity
    workload_identity = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.workload_identity}-${local.region_abbv}",

    # Federated Identity
    federated_identity = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.federated_identity}-${local.region_abbv}",

    # Log Analytics Workspace
    log_analytics_workspace = "${local.default_prefix}-${var.environment}-${local.resource_types.log_analytics_workspace}-${local.region_abbv}",

    # App Service
    app_service = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.app_service}-${local.region_abbv}",

    # Function App
    function_app = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.function_app}-${local.region_abbv}",

    # Virtual Network
    virtual_network = "${local.default_prefix}-${var.environment}-${local.resource_types.virtual_network}-${local.region_abbv}",

    # Subnet (base name)
    subnet = "${local.default_prefix}-${var.environment}-${local.resource_types.subnet}",

    # Front Door
    front_door = "${local.default_prefix}-${var.environment}-${local.resource_types.front_door}-${local.region_abbv}",

    # Front Door Profile
    frontdoor_profile = "${local.default_prefix}-${var.environment}-${local.resource_types.frontdoor_profile}-${local.region_abbv}",

    # Front Door Endpoint
    frontdoor_endpoint = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.frontdoor_endpoint}-${local.region_abbv}",

    # Front Door Origin Group
    frontdoor_origin_group = "${local.default_prefix}-${var.environment}-${local.resource_types.frontdoor_origin_group}-${local.region_abbv}",

    # Front Door Origin
    frontdoor_origin = "${local.default_prefix}-${var.environment}-${local.resource_types.frontdoor_origin}-${local.region_abbv}",

    # Front Door Route
    frontdoor_route = "${local.default_prefix}-${var.environment}-${local.resource_types.frontdoor_route}-${local.region_abbv}",

    # Container Registry (no hyphens)
    container_registry = "${local.default_prefix}${local.normalized_customer}${var.environment}${local.resource_types.container_registry}${local.region_abbv}",
    
    # Event Hub Namespace
    event_hub_namespace = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.event_hub_namespace}-${local.region_abbv}",

    # Event Hub
    event_hub = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.event_hub}-${local.region_abbv}",

    # Monitor Workspace 
    monitor_workspace = "${local.default_prefix}-${var.environment}-${local.resource_types.monitor_workspace}-${local.region_abbv}",

    # Application Insights
    application_insights = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.application_insights}-${local.region_abbv}",

    # App Configuration
    app_configuration = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.app_configuration}-${local.region_abbv}",

    # SQL Server
    sql_server = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.sql_server}-${local.region_abbv}",

    # SQL Database
    sql_database = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.sql_database}-${local.region_abbv}",

    # Cosmos DB Account
    cosmos_account = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.cosmos_account}-${local.region_abbv}",

    # Network Security Group
    network_security_group = "${local.default_prefix}-${var.environment}-${local.resource_types.network_security_group}-${local.region_abbv}",

    # Route Table
    route_table = "${local.default_prefix}-${var.environment}-${local.resource_types.route_table}-${local.region_abbv}",

    # Bastion Host
    bastion_host = "${local.default_prefix}-${var.environment}-${local.resource_types.bastion_host}-${local.region_abbv}",

    # Private Endpoint
    private_endpoint = "${local.default_prefix}${local.customer_part}-${var.environment}-${local.resource_types.private_endpoint}-${local.region_abbv}",

    # Public IP
    public_ip = "${local.default_prefix}-${var.environment}-${local.resource_types.public_ip}-${local.region_abbv}",

    # Load Balancer
    load_balancer = "${local.default_prefix}-${var.environment}-${local.resource_types.load_balancer}-${local.region_abbv}",

    # AKS Node Pool (special format with no hyphens, 12 char limit)
    aks_node_pool = "${local.default_prefix}${var.environment}${local.resource_types.aks_node_pool}",

    # Managed Prometheus for AKS
    managed_prometheus = "${local.default_prefix}-${var.environment}-${local.resource_types.managed_prometheus}-${local.region_abbv}",

    # Container Insights for AKS
    container_insights = "${local.default_prefix}-${var.environment}-${local.resource_types.container_insights}-${local.region_abbv}",

    # AKS Identity
    aks_identity = "${local.default_prefix}-${var.environment}-${local.resource_types.aks_identity}-${local.region_abbv}"
  }

  # Function to generate subnet names (workaround for HCL syntax limitations)
  subnet_name = "${local.default_prefix}-${var.environment}-${local.resource_types.subnet}"

  # Common subnet types
  subnet_node     = "${local.subnet_name}-node-${local.region_abbv}"
  subnet_api      = "${local.subnet_name}-api-${local.region_abbv}"
  subnet_app      = "${local.subnet_name}-app-${local.region_abbv}"
  subnet_db       = "${local.subnet_name}-db-${local.region_abbv}"
  subnet_endpoint = "${local.subnet_name}-endpoint-${local.region_abbv}"
  subnet_service  = "${local.subnet_name}-service-${local.region_abbv}"
  subnet_gateway  = "${local.subnet_name}-gateway-${local.region_abbv}"

  # Validate names against Azure restrictions and truncate if necessary
  validated_names = {
    for resource_type, name in local.names :
    resource_type => (
      contains(keys(local.naming_rules), resource_type) ? (
        length(name) > local.naming_rules[resource_type].max_length ?
        substr(name, 0, local.naming_rules[resource_type].max_length) :
        lookup(local.naming_rules[resource_type], "no_hyphens", false) ? replace(name, "-", "") : name
      ) : name
    )
  }
}

# Generate monitor workspace (Prometheus) name
module "monitor_workspace" {
  source = "Azure/naming/azurerm"
  suffix = [var.environment, var.region_abbv]
  prefix = [var.prefix]
  unique-include-numbers = false
  unique-length = 0
  unique-seed = var.unique_seed
}

# Generate Grafana name
module "grafana" {
  source = "Azure/naming/azurerm"
  suffix = [var.environment, var.region_abbv]
  prefix = [var.prefix]
  unique-include-numbers = false
  unique-length = 0
  unique-seed = var.unique_seed
}

# Container Registry names must be globally unique, 5-50 characters, alphanumeric only
locals {
  container_registry_name = lower("${var.prefix}${var.environment}acr${var.region_abbv}")
} 