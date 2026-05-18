# Azure Monitor Workspace - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for deploying and managing an Azure Monitor Workspace in the East US region for the development environment. The Monitor Workspace serves as a centralized repository for metrics data and is essential for Prometheus integration with AKS.

## Configuration Details

### Purpose

This configuration:
- Creates an Azure Monitor Workspace for storing and managing metrics data
- Provides a foundation for Prometheus metrics collection from Kubernetes
- Enables advanced monitoring capabilities for containerized applications
- Integrates with other Azure monitoring services for comprehensive observability

### Dependencies

This configuration depends on:
- **naming**: Uses standardized resource naming conventions
- **resource_group**: Deploys resources in the specified resource group

### Key Configuration Settings

- **Workspace Configuration**:
  - Name: Follows naming convention from the naming module
  - Location: East US (same as resource group)
  - Plan: Pay-as-you-go (standard pricing for metrics)

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/monitor_workspace
terragrunt plan
terragrunt apply
```

To view monitor workspace details after deployment:

```bash
cd infra/live/azure/dev/eastus/monitor_workspace
terragrunt output id
```

## Dependencies on this Configuration

The following modules depend on outputs from this configuration:
- prometheus_dcr (for Prometheus data collection rules)
- aks_core (for AKS Prometheus integration)
- Any monitoring and alerting modules that use metrics data

## Implementation Notes

Azure Monitor Workspace is a managed service that provides storage for metrics data. It is particularly important for AKS monitoring using Prometheus. The workspace is configured with default settings appropriate for a development environment.

For production environments, consider implementing metric retention policies, access controls, and configuring alerting rules on key metrics. Also, ensure proper integration with Log Analytics Workspace for logs alongside metrics data for complete observability.

After applying this module, you'll need to deploy the Prometheus Data Collection Rule (DCR) module to configure metrics collection from your AKS clusters. 