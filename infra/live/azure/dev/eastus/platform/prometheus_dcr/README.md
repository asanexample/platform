# Azure Prometheus Data Collection Rule - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for deploying and managing an Azure Prometheus Data Collection Rule (DCR) in the East US region for the development environment. The DCR and accompanying Data Collection Endpoint (DCE) are used to collect Prometheus metrics from AKS clusters.

## Configuration Details

### Purpose

This configuration:
- Creates a Data Collection Rule (DCR) for Prometheus metrics collection
- Deploys a Data Collection Endpoint (DCE) for receiving metrics data
- Enables native Azure Monitor integration with Prometheus metrics
- Configures appropriate scraping settings for Kubernetes workloads
- Provides foundation for metrics-based monitoring and alerting

### Dependencies

This configuration depends on:
- **resource_group**: Deploys resources in the specified resource group
- **monitor_workspace**: Uses Azure Monitor Workspace for metrics storage

### Key Configuration Settings

- **Data Collection Rule Configuration**:
  - Default name generation based on convention
  - Linked to the Azure Monitor Workspace for metrics storage
  - Configured for Prometheus metrics collection

- **Data Collection Endpoint Configuration**:
  - Default name generation based on convention
  - Deployed in the same resource group and location

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/prometheus_dcr
terragrunt plan
terragrunt apply
```

To view the DCR details after deployment:

```bash
cd infra/live/azure/dev/eastus/prometheus_dcr
terragrunt output dcr_id
```

## Dependencies on this Configuration

The following modules depend on outputs from this configuration:
- aks_core (references the DCR for Prometheus integration)
- Any monitoring or alerting modules that rely on Prometheus metrics

## Implementation Notes

The Prometheus Data Collection Rule is a key component for monitoring containerized applications in AKS. It enables Azure Monitor to collect and store Prometheus-formatted metrics, providing visibility into the health and performance of Kubernetes workloads.

After deploying this module, you'll need to ensure that AKS is configured to use this DCR by specifying the DCR ID in the AKS configuration. This module works alongside the Azure Monitor Workspace to create a complete metrics collection pipeline.

For production environments, consider customizing the scraping configuration to optimize performance and costs based on your specific workload requirements. 