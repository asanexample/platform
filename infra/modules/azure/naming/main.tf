locals {
  # Workload name and abbreviated form for tight-constraint resources
  default_workload = var.workload

  workload_abbreviations = {
    platform     = "plat"
    connectivity = "conn"
    data         = "data"
    hipaa        = "hipa"
    pci          = "pci"
    shared       = "shrd"
    mgmt         = "mgmt"
  }

  abbreviated_workload = lookup(
    local.workload_abbreviations,
    local.default_workload,
    substr(local.default_workload, 0, 4)
  )

  region_abbv = var.region_abbv

  # Resource type abbreviations
  resource_types = {
    resource_group           = "rg"
    storage_account          = "st"
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
    subnet                   = "snet"
    network_security_group   = "nsg"
    application_gateway      = "agw"
    front_door               = "fd"
    frontdoor_profile        = "fd"
    frontdoor_endpoint       = "fde"
    frontdoor_origin_group   = "fdog"
    frontdoor_origin         = "fdo"
    frontdoor_route          = "fdr"
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
    bastion_host             = "bas"
    route_table              = "rt"
    private_endpoint         = "pe"
    private_dns_zone         = "pdns"
    public_ip                = "pip"
    load_balancer            = "lb"
    aks_node_pool            = "np"
    managed_prometheus       = "prom"
    container_insights       = "ci"
    aks_identity             = "aksid"
    managed_grafana          = "graf"
    action_group             = "ag"
    metric_alert             = "ma"
    activity_log_alert       = "ala"
    diagnostic_setting       = "diag"
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
    action_group = {
      max_length  = 260
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    metric_alert = {
      max_length  = 260
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    activity_log_alert = {
      max_length  = 260
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
    diagnostic_setting = {
      max_length  = 260
      valid_chars = "^[a-zA-Z0-9\\-_]+$"
    }
  }

  # CAF-aligned naming: {type}-{workload}-{env}-{region}
  # For no-hyphen resources: {type}{abbreviated_workload}{env}{region}
  names = {
    resource_group          = "${local.resource_types.resource_group}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    storage_account         = "${local.resource_types.storage_account}${local.abbreviated_workload}${var.environment}${local.region_abbv}"
    key_vault               = "${local.resource_types.key_vault}-${local.abbreviated_workload}-${var.environment}-${local.region_abbv}"
    aks_cluster             = "${local.resource_types.aks_cluster}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    workload_identity       = "${local.resource_types.workload_identity}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    federated_identity      = "${local.resource_types.federated_identity}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    log_analytics_workspace = "${local.resource_types.log_analytics_workspace}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    app_service             = "${local.resource_types.app_service}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    function_app            = "${local.resource_types.function_app}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    virtual_network         = "${local.resource_types.virtual_network}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    subnet                  = "${local.resource_types.subnet}-${local.default_workload}-${var.environment}"
    front_door              = "${local.resource_types.front_door}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    frontdoor_profile       = "${local.resource_types.frontdoor_profile}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    frontdoor_endpoint      = "${local.resource_types.frontdoor_endpoint}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    frontdoor_origin_group  = "${local.resource_types.frontdoor_origin_group}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    frontdoor_origin        = "${local.resource_types.frontdoor_origin}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    frontdoor_route         = "${local.resource_types.frontdoor_route}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    container_registry      = "${local.resource_types.container_registry}${local.abbreviated_workload}${var.environment}${local.region_abbv}"
    event_hub_namespace     = "${local.resource_types.event_hub_namespace}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    event_hub               = "${local.resource_types.event_hub}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    monitor_workspace       = "${local.resource_types.monitor_workspace}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    application_insights    = "${local.resource_types.application_insights}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    app_configuration       = "${local.resource_types.app_configuration}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    sql_server              = "${local.resource_types.sql_server}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    sql_database            = "${local.resource_types.sql_database}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    cosmos_account          = "${local.resource_types.cosmos_account}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    network_security_group  = "${local.resource_types.network_security_group}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    route_table             = "${local.resource_types.route_table}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    bastion_host            = "${local.resource_types.bastion_host}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    private_endpoint        = "${local.resource_types.private_endpoint}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    public_ip               = "${local.resource_types.public_ip}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    load_balancer           = "${local.resource_types.load_balancer}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    aks_node_pool           = "${local.resource_types.aks_node_pool}${local.abbreviated_workload}${var.environment}"
    managed_prometheus      = "${local.resource_types.managed_prometheus}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    container_insights      = "${local.resource_types.container_insights}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    aks_identity            = "${local.resource_types.aks_identity}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    managed_grafana         = "${local.resource_types.managed_grafana}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    action_group            = "${local.resource_types.action_group}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    metric_alert            = "${local.resource_types.metric_alert}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    activity_log_alert      = "${local.resource_types.activity_log_alert}-${local.default_workload}-${var.environment}-${local.region_abbv}"
    diagnostic_setting      = "${local.resource_types.diagnostic_setting}-${local.default_workload}-${var.environment}-${local.region_abbv}"
  }

  # Subnet naming helpers
  subnet_name     = "${local.resource_types.subnet}-${local.default_workload}-${var.environment}"
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
  source                  = "Azure/naming/azurerm"
  suffix                  = [var.environment, var.region_abbv]
  prefix                  = [var.workload]
  unique-include-numbers  = false
  unique-length           = 0
  unique-seed             = var.unique_seed
}

# Generate Grafana name
module "grafana" {
  source                  = "Azure/naming/azurerm"
  suffix                  = [var.environment, var.region_abbv]
  prefix                  = [var.workload]
  unique-include-numbers  = false
  unique-length           = 0
  unique-seed             = var.unique_seed
}

# Container Registry names must be globally unique, 5-50 characters, alphanumeric only
locals {
  container_registry_name = lower("${local.resource_types.container_registry}${local.abbreviated_workload}${var.environment}${var.region_abbv}")
}
