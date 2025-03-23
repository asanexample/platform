# Container Insights DCR Module

## Overview

This module creates the necessary Azure Monitor Agent (AMA) Data Collection Rules (DCR) for Azure Container Insights. It's designed to replace the legacy Log Analytics Agent (MMA/OMS) which will be retired on August 31, 2024.

## Features

- Creates a Data Collection Rule (DCR) for Container Insights monitoring
- Associates the DCR with an AKS cluster
- Configures appropriate data streams for container monitoring
- Supports customizable collection intervals and namespace filtering
- Uses the newer ContainerLogV2 format by default

## Usage

```hcl
module "container_insights_dcr" {
  source = "../../modules/azure/container_insights_dcr"

  resource_group_name       = azurerm_resource_group.example.name
  location                  = azurerm_resource_group.example.location
  cluster_name              = azurerm_kubernetes_cluster.example.name
  cluster_id                = azurerm_kubernetes_cluster.example.id
  log_analytics_workspace_id = azurerm_log_analytics_workspace.example.id
  
  # Optional configurations
  interval                  = "1m"
  namespace_filtering_mode  = "Include"
  namespaces                = ["kube-system"]
  enable_container_log_v2   = true
  
  tags = {
    environment = "production"
    component   = "monitoring"
  }
}
```

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| resource_group_name | The name of the resource group in which to create the DCR | string |
| location | The Azure region where the DCR should be created | string |
| cluster_name | The name of the AKS cluster | string |
| cluster_id | The ID of the AKS cluster | string |
| log_analytics_workspace_id | The ID of the Log Analytics workspace for Container Insights | string |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| data_streams | The data streams to collect from the AKS cluster | list(string) | ["Microsoft-ContainerLogV2", "Microsoft-Perf", "Microsoft-KubeEvents", "Microsoft-KubePodInventory", "Microsoft-KubeNodeInventory", "Microsoft-KubeServices", "Microsoft-KubePVInventory"] |
| interval | The interval at which data is collected (e.g., '1m') | string | "1m" |
| namespace_filtering_mode | The namespace filtering mode (Include or Exclude) | string | "Include" |
| namespaces | The list of namespaces to include or exclude | list(string) | ["kube-system"] |
| enable_container_log_v2 | Whether to enable the newer ContainerLogV2 format | bool | true |
| tags | Tags to apply to all resources | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Container Insights DCR |
| name | The name of the Container Insights DCR |
| association_id | The ID of the DCR association |

## Notes

- This module requires Azure Provider version 4.23.0 or higher
- AMA replaces the deprecated Log Analytics Agent (MMA/OMS)
- Both agents can exist side by side, but you should plan to remove the legacy agent to avoid duplicate data 