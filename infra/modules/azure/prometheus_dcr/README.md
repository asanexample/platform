# Azure Prometheus Data Collection Rule Module

## Overview

This module creates an Azure Monitor Data Collection Rule (DCR) and Data Collection Endpoint (DCE) specifically configured for collecting Prometheus metrics from Azure Kubernetes Service (AKS) clusters. The collected metrics are sent to an Azure Monitor workspace, enabling a managed Prometheus solution without the need to manage a separate Prometheus instance.

## Features

- Creates a Data Collection Rule (DCR) for Prometheus metrics collection
- Provisions a Data Collection Endpoint (DCE) for Prometheus metrics ingestion
- Configures proper data flow to an Azure Monitor workspace
- Supports automated naming with sensible defaults
- Includes comprehensive input validation for all parameters
- Ensures proper configuration for AKS Prometheus metrics scraping

## Usage

```hcl
module "prometheus_dcr" {
  source = "../../modules/azure/prometheus_dcr"

  resource_group_name  = "rg-monitoring-prod-eastus"
  location             = "eastus"
  monitor_workspace_id = module.monitor_workspace.id
  
  # Optional custom names
  name     = "dcr-prometheus-aks"
  dce_name = "dce-prometheus-aks"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
  }
}
```

## Examples

### Basic Prometheus DCR

```hcl
module "prometheus_dcr" {
  source = "../../modules/azure/prometheus_dcr"

  resource_group_name  = "rg-monitoring-dev-eastus"
  location             = "eastus"
  monitor_workspace_id = module.monitor_workspace.id
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Production Prometheus DCR with Custom Names

```hcl
module "prometheus_dcr" {
  source = "../../modules/azure/prometheus_dcr"

  resource_group_name  = "rg-monitoring-prod-eastus"
  location             = "eastus"
  monitor_workspace_id = module.monitor_workspace.id
  
  name     = "dcr-prometheus-prod-aks"
  dce_name = "dce-prometheus-prod-aks"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
    CostCenter  = "Platform"
  }
}
```

### Multi-Region Prometheus DCR Setup

```hcl
# Primary region
module "prometheus_dcr_eastus" {
  source = "../../modules/azure/prometheus_dcr"

  resource_group_name  = "rg-monitoring-prod-eastus"
  location             = "eastus"
  monitor_workspace_id = module.monitor_workspace.id
  
  name     = "dcr-prometheus-eastus"
  dce_name = "dce-prometheus-eastus"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Region      = "East US"
  }
}

# Secondary region
module "prometheus_dcr_westus" {
  source = "../../modules/azure/prometheus_dcr"

  resource_group_name  = "rg-monitoring-prod-westus"
  location             = "westus"
  monitor_workspace_id = module.monitor_workspace.id
  
  name     = "dcr-prometheus-westus"
  dce_name = "dce-prometheus-westus"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Region      = "West US"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| resource_group_name | The name of the resource group to deploy the DCR and DCE in | `string` |
| location | The Azure region where the DCR and DCE will be deployed | `string` |
| monitor_workspace_id | The resource ID of the Azure Monitor Workspace to send metrics to | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Optional base name for the DCR (e.g., 'dcr-prometheus') | `string` | `null` | no |
| dce_name | Optional name for the Data Collection Endpoint (DCE) | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| dcr_id | The ID of the created Data Collection Rule |
| dcr_name | The name of the created Data Collection Rule |
| dce_id | The ID of the created Data Collection Endpoint |
| dce_name | The name of the created Data Collection Endpoint |

## Module Resources

This module creates the following resources:
- Azure Monitor Data Collection Rule (DCR)
- Azure Monitor Data Collection Endpoint (DCE)

## Dependencies

This module depends on:
- [resource_group](../resource_group) - For resource group creation
- [monitor_workspace](../monitor_workspace) - For the Azure Monitor workspace to send metrics to

## Integration with AKS

To integrate with an AKS cluster, you need to:

1. Create the Prometheus DCR using this module
2. Associate the DCR with your AKS cluster using the Azure Monitor agent

Here's an example of how to associate the DCR with an AKS cluster:

```hcl
resource "azurerm_monitor_data_collection_rule_association" "example" {
  name                    = "dcra-prometheus-aks"
  target_resource_id      = module.aks.id
  data_collection_rule_id = module.prometheus_dcr.dcr_id
}
```

This can be done using the [aks_core](../aks_core) module with the appropriate configuration.

## Prometheus Metrics Collection

This module configures the DCR to collect Prometheus metrics using the following setup:

1. A Linux-type Data Collection Endpoint (DCE) for receiving Prometheus metrics
2. A Linux-type Data Collection Rule (DCR) with a Prometheus forwarder data source
3. A data flow configuration that sends Microsoft-PrometheusMetrics to the Azure Monitor workspace

The metrics are collected using the Azure Monitor agent on AKS nodes, which scrapes the Prometheus endpoints and forwards the metrics to the DCE.

## Notes

- The DCR and DCE names have validation rules: 3-63 characters, alphanumeric, hyphens, and underscores only
- The resource group name has validation rules: 3-63 characters, alphanumeric, hyphens, underscores, parentheses, and periods
- The location must be a valid Azure region name
- The monitor workspace ID must be a valid Azure Monitor workspace resource ID
- Default names are generated based on the location if not provided
- For production environments, consider using custom names for better identification
- The DCR and DCE are region-specific, so you may need to create multiple instances for multi-region deployments

## Implementation Notes

### Operational Considerations
- **Metric Selection**: By default, this DCR collects all Prometheus metrics; consider using namespace or label filters to limit collection to only necessary metrics
- **Scrape Interval**: The default scrape interval is 60 seconds; adjust this based on your application's requirements and cost considerations
- **Resource Requirements**: The Azure Monitor agent consumes additional resources on your AKS nodes; ensure your node pools have sufficient capacity
- **Quota Limits**: Be aware of Azure Monitor service limits for metrics ingestion rates and adjust your collection strategy accordingly

### Troubleshooting Guidance
- **Missing Metrics**: If metrics aren't appearing, verify:
  1. The DCR association with the AKS cluster is active
  2. The Azure Monitor agent pods are running in the kube-system namespace
  3. Applications are exposing Prometheus metrics on the expected endpoints
  4. Network connectivity between agent and applications is working
- **High Latency**: If experiencing high metric latency:
  1. Check if the Monitor Workspace is in the same region as your AKS cluster
  2. Verify agent pods have adequate resources
  3. Consider reducing the volume of metrics being collected

### Scaling Recommendations
- **Large Clusters**: For clusters with many nodes (>100), consider:
  1. Using multiple smaller node pools to distribute monitoring agent load
  2. Implementing metric collection sampling for high-volume metrics
  3. Setting up dedicated node pools for system components including monitoring
- **Multi-Cluster Configuration**: When monitoring multiple clusters:
  1. Use a consistent naming convention for DCRs and DCEs across clusters
  2. Consider using a dedicated Monitor Workspace for critical production clusters
  3. Implement proper tagging to distinguish metrics from different clusters

### Security Practices
- **RBAC Controls**: Limit access to the DCR and DCE management to platform administrators only
- **Network Security**: If using private AKS clusters, ensure the DCE can communicate with your cluster's private endpoints
- **Data Segregation**: Use separate Monitor Workspaces for production and non-production environments to maintain data isolation
- **Least Privilege**: The Azure Monitor agent requires specific permissions; avoid granting excessive permissions beyond what's needed

### Integration with Monitoring Strategy
- **Complete Observability**: Combine with:
  1. Log Analytics Workspace for log collection
  2. Application Insights for application telemetry
  3. Azure Monitor Alerts for proactive notifications
- **Dashboarding Strategy**: Create dedicated Grafana dashboards for:
  1. Cluster health and performance
  2. Application-specific metrics
  3. Business KPIs derived from application metrics
- **Cost Management**: Regularly review:
  1. Metric volume and ingestion rates
  2. Unnecessary metrics being collected
  3. Opportunities to aggregate or downsample metrics before ingestion

### Related Documentation
- [Azure Monitor Managed Service for Prometheus](https://docs.microsoft.com/en-us/azure/azure-monitor/containers/prometheus-metrics-enable)
- [Prometheus Scraping Configuration](https://prometheus.io/docs/prometheus/latest/configuration/configuration/)
- [Prometheus Query Language (PromQL)](https://prometheus.io/docs/prometheus/latest/querying/basics/)

## License

This module is licensed under the MIT License. 