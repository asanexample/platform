/**
 * Creates an Azure Monitor Data Collection Rule (DCR) and Data Collection Endpoint (DCE)
 * specifically configured for AKS Prometheus metrics scraping.
 */

locals {
  dcr_name = var.name != null ? var.name : "dcr-prometheus-${var.location}"
  dce_name = var.dce_name != null ? var.dce_name : "dce-prometheus-${var.location}"
}

# Create the Data Collection Endpoint (DCE)
resource "azurerm_monitor_data_collection_endpoint" "this" {
  count               = var.create ? 1 : 0
  name                = local.dce_name
  resource_group_name = var.resource_group_name
  location            = var.location
  kind                = "Linux" # Required for Prometheus
  tags                = var.tags
}

# Create the Data Collection Rule (DCR)
resource "azurerm_monitor_data_collection_rule" "this" {
  count                       = var.create ? 1 : 0
  name                        = local.dcr_name
  resource_group_name         = var.resource_group_name
  location                    = var.location
  data_collection_endpoint_id = azurerm_monitor_data_collection_endpoint.this[0].id
  kind                        = "Linux" # Required for Prometheus

  data_sources {
    prometheus_forwarder {
      name    = "PrometheusDataSource"
      streams = ["Microsoft-PrometheusMetrics"]
    }
  }

  destinations {
    monitor_account {
      monitor_account_id = var.monitor_workspace_id
      name               = "MonitoringAccount"
    }
  }

  data_flow {
    destinations = ["MonitoringAccount"]
    streams      = ["Microsoft-PrometheusMetrics"]
  }

  tags = var.tags
} 