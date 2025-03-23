# Container Insights DCR - East US (Dev)

## Overview

This directory configures Data Collection Rules (DCR) for Container Insights using the Azure Monitor Agent (AMA) for the development environment in East US. It replaces the deprecated Log Analytics Agent (MMA/OMS) which will be retired on August 31, 2024.

## Configuration Details

### Purpose

Creates Azure Monitor Agent (AMA) configuration for AKS monitoring:
- Defines what container and Kubernetes data to collect
- Sets collection intervals and filtering
- Associates the configuration with the AKS cluster
- Routes collected data to the Log Analytics workspace

### Dependencies

- **resource_group**: Deploys DCR in the shared resource group
- **log_analytics**: Uses the Log Analytics workspace for data storage
- **aks_core**: Associates the DCR with the AKS cluster

### Configuration Settings

- **Collection Interval**: 1 minute (configurable)
- **Namespace Filtering**: Focused on critical namespaces (`kube-system`)
- **Container Logs Format**: Using the newer ContainerLogV2 format
- **Data Streams**: 
  - Microsoft-ContainerLogV2 (container logs)
  - Microsoft-Perf (performance metrics)
  - Microsoft-KubeEvents (Kubernetes events)
  - Microsoft-KubePodInventory (pod inventory)
  - Microsoft-KubeNodeInventory (node inventory)
  - Microsoft-KubeServices (services inventory)

## Implementation Notes

This configuration sets up the AMA-based monitoring that replaces the legacy Log Analytics Agent. Key advantages include:
- More efficient data collection
- Improved container log format
- Namespaced-based filtering
- Lower resource utilization

## Usage

To apply this module:
```bash
cd container_insights_dcr
terragrunt apply
```

## Migration

This module is part of the migration from Log Analytics Agent to Azure Monitor Agent. After deploying this module:
1. Verify data appears in Container Insights dashboards
2. Both agents can run simultaneously during transition
3. Eventually remove Log Analytics Agent references to avoid duplicate data 