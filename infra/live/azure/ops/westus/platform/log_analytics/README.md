# Log Analytics Workspace for AKS Monitoring (Ops Environment)

This directory contains the Terragrunt configuration for deploying an Azure Log Analytics Workspace in the westus region for the ops environment.

## Purpose

This Log Analytics Workspace serves as the foundation for monitoring the AKS cluster and other Azure resources in the operations environment. It provides enhanced retention and monitoring capabilities appropriate for a production-like environment.

## Features

- Collects logs from the AKS cluster and containers
- Provides a query interface for analyzing logs and metrics
- Serves as a data store for diagnostic settings
- Enables Container Insights for detailed Kubernetes monitoring
- Includes Security solutions for enhanced security monitoring
- **Extended 60-day log retention** for operations environment

## Integration Points

The Log Analytics Workspace integrates with:

- AKS Cluster: Collects logs from the Kubernetes control plane and nodes
- Container Insights: Provides specialized monitoring for containers
- Azure Monitor: Enables alerting and dashboards
- Security Center: Enhances security monitoring capabilities

## How to Deploy

To deploy this Log Analytics Workspace:

```bash
cd infra/live/azure/ops/westus/log_analytics
terragrunt init
terragrunt plan
terragrunt apply
```

## Connecting to AKS

After deploying the Log Analytics Workspace, enable monitoring for the AKS cluster by updating the AKS configuration to include this workspace ID. 