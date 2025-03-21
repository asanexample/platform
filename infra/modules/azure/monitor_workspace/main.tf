/**
 * # Azure Monitor Workspace Module (Managed Prometheus)
 *
 * This module creates an Azure Monitor workspace, which serves as the backend for 
 * Azure Managed Prometheus metrics from AKS clusters.
 */

resource "azurerm_monitor_workspace" "prometheus" {
  name                = var.name
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = var.tags
}

# Data Collection Endpoint - required for Prometheus metrics collection
resource "azurerm_monitor_data_collection_endpoint" "prometheus" {
  name                = "${var.name}-dce"
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux"
  description         = "Data Collection Endpoint for Prometheus metrics"
  tags                = var.tags
}

# Data Collection Rule for AKS Prometheus metrics
resource "azurerm_monitor_data_collection_rule" "prometheus" {
  name                        = "${var.name}-dcr"
  resource_group_name         = var.resource_group_name
  location                    = var.location
  kind                        = "Linux"
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.prometheus.id
  
  destinations {
    monitor_account {
      monitor_account_id = azurerm_monitor_workspace.prometheus.id
      name               = "MonitoringAccount1"
    }
  }
  
  data_flow {
    streams      = ["Microsoft-PrometheusMetrics"]
    destinations = ["MonitoringAccount1"]
  }
  
  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }
  
  description = "Data Collection Rule for AKS Prometheus metrics"
  tags        = var.tags
  
  depends_on = [
    azurerm_monitor_workspace.prometheus
  ]
} 