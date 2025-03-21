# Azure Log Analytics Workspace - East US (Dev)

## Overview
This module provisions and configures an Azure Log Analytics workspace in the East US region for the development environment. It serves as the central logging and monitoring solution for various Azure resources, with particular focus on AKS monitoring.

## Configuration Details

### Purpose
Creates a production-ready Log Analytics workspace that:
- Provides centralized logging and monitoring capabilities
- Enables advanced analytics for security and operational insights
- Supports integration with multiple Azure services
- Serves as the foundation for observability and diagnostics

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group

### Key Configuration Settings
- **Workspace Configuration**:
  - SKU: PerGB2018 (Pay-as-you-go pricing model)
  - Retention Period: 30 days
  - Internet Ingestion: Enabled
  - Internet Query: Enabled
- **Solution Packs**:
  - ContainerInsights: For AKS monitoring
  - Security: For security monitoring
  - AzureActivity: For auditing Azure activities
- **Diagnostic Settings**:
  - Self-monitoring: Logs for the workspace itself
  - Metrics Collection: All metrics captured for performance analysis
  - Audit Logs: Tracking access and configuration changes

## Implementation Details
The Log Analytics module creates a standardized workspace environment with:
- Optimal configuration for cloud-native workloads
- Support for container monitoring with ContainerInsights
- Security monitoring and compliance reporting
- Integration with AKS and other Azure resources

## Integration with AKS
The Log Analytics workspace provides monitoring for the AKS cluster with:
- Container insights for pod and node monitoring
- Control plane logs for Kubernetes API server, scheduler, etc.
- Metrics for cluster performance analysis
- Custom queries and dashboards

## Usage Example

To apply this module:
```bash
cd log_analytics
terragrunt apply
```

To query logs after deployment:
```bash
# View API server errors in the last hour
az monitor log-analytics query \
  --workspace $(terragrunt output id) \
  --query "AzureDiagnostics | where Category == 'kube-apiserver' and TimeGenerated > ago(1h) and Level == 'Error' | project TimeGenerated, Log" \
  --analytics-query
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- aks_core

## Maintenance and Operations
The Log Analytics workspace is configured with a 30-day retention period. For longer-term storage, consider:
- Exporting logs to Azure Storage for archival
- Setting up Log Analytics workspace-level alerts for quota management
- Regularly reviewing data ingestion to optimize costs 