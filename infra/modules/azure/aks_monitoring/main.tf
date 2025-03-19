/**
 * # AKS Monitoring Module
 *
 * This module configures monitoring for AKS clusters, including Log Analytics integration,
 * diagnostic settings, and Azure Monitor for Containers.
 */

# Use the naming module to generate standardized names
module "naming" {
  source = "../naming"

  prefix      = var.prefix
  customer    = var.customer
  stage       = var.stage
  region_abbv = var.region_abbv
}

locals {
  # Generate resource names if not provided
  diagnostic_setting_name = var.diagnostic_setting_name != null ? var.diagnostic_setting_name : "${var.cluster_name}-diag"
  prometheus_dce_name = var.prometheus_dce_name != null ? var.prometheus_dce_name : "${var.cluster_name}-prometheus-dce"
  prometheus_dcr_name = var.prometheus_dcr_name != null ? var.prometheus_dcr_name : "${var.cluster_name}-prometheus-dcr"
  container_insights_dcr_name = var.container_insights_dcr_name != null ? var.container_insights_dcr_name : "${var.cluster_name}-container-insights-dcr"
}

# Configure diagnostic settings for the AKS cluster
resource "azurerm_monitor_diagnostic_setting" "aks_cluster_diagnostic_setting" {
  name                       = local.diagnostic_setting_name
  target_resource_id         = var.cluster_id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  # Enable all relevant logs
  dynamic "log" {
    for_each = var.log_categories
    content {
      category = log.value
      enabled  = true
      
      retention_policy {
        enabled = true
        days    = 30
      }
    }
  }

  # Enable metrics
  dynamic "metric" {
    for_each = var.metric_categories
    content {
      category = metric.value
      enabled  = true
      
      retention_policy {
        enabled = true
        days    = 30
      }
    }
  }
}

# Create data collection endpoint for Prometheus metrics
resource "azurerm_monitor_data_collection_endpoint" "aks_dce" {
  count               = var.enable_prometheus ? 1 : 0
  name                = local.prometheus_dce_name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  
  tags = merge(var.tags, {
    name = local.prometheus_dce_name
  })
}

# Create data collection rule for Prometheus metrics
resource "azurerm_monitor_data_collection_rule" "aks_dcr" {
  count               = var.enable_prometheus ? 1 : 0
  name                = local.prometheus_dcr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "ciworkspace"
    }
  }

  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.aks_dce[0].id

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["ciworkspace"]
  }

  description = "DCR for AKS Prometheus metrics"
  
  tags = merge(var.tags, {
    name = local.prometheus_dcr_name
  })
}

# Associate the Prometheus data collection rule with the AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "aks_dcr_association" {
  count                   = var.enable_prometheus ? 1 : 0
  name                    = "prometheus-association"
  target_resource_id      = var.cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.aks_dcr[0].id
  description             = "Association for AKS Prometheus metrics"
}

# Grant publisher permissions for Prometheus metrics
resource "azurerm_role_assignment" "remote_write_monitoring_metrics_publisher_role_assignment" {
  count               = var.enable_prometheus ? 1 : 0
  scope                = azurerm_monitor_data_collection_rule.aks_dcr[0].id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = "system:serviceaccount:kube-system:prometheus-ama-remote-write"
}

# Create data collection rule for Container Insights
resource "azurerm_monitor_data_collection_rule" "container_insights_dcr" {
  count               = var.enable_container_insights ? 1 : 0
  name                = local.container_insights_dcr_name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"

  destinations {
    log_analytics {
      workspace_resource_id = var.log_analytics_workspace_id
      name                  = "ciworkspace"
    }
  }

  data_sources {
    extension {
      name           = "ContainerInsights"
      extension_name = "ContainerInsights"
      streams        = ["Microsoft-ContainerInsights-Group-Default"]
      # Container Insights extension settings configuration - simplified
      # Extension settings are configured internally by Azure
    }

    syslog {
      name           = "sysLogsDataSource"
      facility_names = var.syslog_facilities
      log_levels     = var.syslog_levels
      streams        = ["Microsoft-Syslog"]
    }
  }

  stream_declaration {
    stream_name = "Microsoft-ContainerInsights-Group-Default"
    column {
      name = "Computer"
      type = "string"
    }
    column {
      name = "SourceSystem"
      type = "string"
    }
  }

  data_flow {
    streams      = ["Microsoft-ContainerInsights-Group-Default"]
    destinations = ["ciworkspace"]
  }

  data_flow {
    streams      = ["Microsoft-Syslog"]
    destinations = ["ciworkspace"]
  }

  description = "DCR for Container Insights"
  
  tags = merge(var.tags, {
    name = local.container_insights_dcr_name
  })
}

# Associate the Container Insights data collection rule with the AKS cluster
resource "azurerm_monitor_data_collection_rule_association" "container_insights_dcra" {
  count                   = var.enable_container_insights ? 1 : 0
  name                    = "container-insights-association"
  target_resource_id      = var.cluster_id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.container_insights_dcr[0].id
  description             = "Association for Container Insights"
} 