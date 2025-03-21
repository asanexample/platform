# Azure Monitor Workspace Module (Managed Prometheus)

## Overview

This module creates an Azure Monitor workspace, which serves as the backend for Azure Managed Prometheus metrics from AKS clusters. It includes all necessary resources for metric collection, including the Monitor workspace, Data Collection Endpoint, and Data Collection Rule.

## Features

- Creates an Azure Monitor workspace for storing Prometheus metrics
- Provisions a Data Collection Endpoint (DCE) for receiving metrics
- Configures a Data Collection Rule (DCR) to route Prometheus metrics to the workspace
- Sets up proper data flow for Microsoft-PrometheusMetrics streams
- Supports tagging for all created resources

## Usage

```hcl
module "prometheus" {
  source = "../../modules/azure/monitor_workspace"

  name                = "aks-prometheus"
  resource_group_name = "monitoring-rg"
  location            = "eastus"
  
  tags = {
    environment = "production"
    application = "aks-monitoring"
    owner       = "platform-team"
  }
}

# Use with AKS cluster for Prometheus metrics collection
resource "azurerm_monitor_data_collection_rule_association" "example" {
  name                    = "aks-prometheus-dcra"
  target_resource_id      = azurerm_kubernetes_cluster.example.id
  data_collection_rule_id = module.prometheus.dcr_id
}
```

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| name | Name of the Azure Monitor workspace | string |
| resource_group_name | Name of the resource group in which to create resources | string |
| location | Azure region where resources should be created | string |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| tags | Tags to apply to all resources | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Monitor workspace |
| name | The name of the Azure Monitor workspace |
| dcr_id | The ID of the Data Collection Rule |
| dce_id | The ID of the Data Collection Endpoint |

## Notes

- Azure Monitor workspace (Managed Prometheus) is designed for containers and AKS monitoring
- To collect metrics from an AKS cluster, you must associate the Data Collection Rule with the cluster
- Azure Managed Prometheus metrics are billed based on data ingestion volume
- The Data Collection Endpoint and Rule are configured specifically for Prometheus metrics collection 