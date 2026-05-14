# Log Analytics Workspace for AKS Monitoring

This directory contains the Terragrunt configuration for deploying an Azure Log Analytics Workspace in the eastus region for the dev environment. 

## Purpose

This Log Analytics Workspace serves as the foundation for monitoring the AKS cluster and other Azure resources. It collects and analyzes logs and telemetry data, providing insights into operational health, performance, and security.

## Features

- Collects logs from the AKS cluster and containers
- Provides a query interface for analyzing logs and metrics
- Serves as a data store for diagnostic settings
- Enables Container Insights for detailed Kubernetes monitoring
- Includes Security solutions for enhanced security monitoring

## Integration Points

The Log Analytics Workspace integrates with:

- AKS Cluster: Collects logs from the Kubernetes control plane and nodes
- Container Insights: Provides specialized monitoring for containers
- Azure Monitor: Enables alerting and dashboards
- Security Center: Enhances security monitoring capabilities

## How to Deploy

To deploy this Log Analytics Workspace:

```bash
cd infra/live/azure/dev/eastus/log_analytics
terragrunt init
terragrunt plan
terragrunt apply
```

## Connecting to AKS

After deploying the Log Analytics Workspace, enable monitoring for the AKS cluster by updating the AKS configuration to include this workspace ID. 