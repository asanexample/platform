# Azure Log Analytics Workspace Module

## Overview

This module creates an Azure Log Analytics Workspace with essential configurations for centralized logging, monitoring, and analytics across Azure resources. It provides comprehensive monitoring capabilities, particularly for Azure Kubernetes Service (AKS) clusters and other Azure services.

## Features

- Creates a Log Analytics Workspace with configurable retention and SKU
- Supports installation of solution packs (ContainerInsights, Security, etc.)
- Configures diagnostic settings for the workspace itself
- Controllable data ingestion limits through daily quotas
- Configurable network access settings for ingestion and querying
- Provides all necessary outputs for integration with other Azure services

## Usage

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                = "law-monitoring-prod-eastus"
  resource_group_name = "rg-monitoring-prod-eastus"
  location            = "eastus"
  sku                 = "PerGB2018"
  retention_in_days   = 30

  solution_plans = [
    {
      solution_name = "ContainerInsights"
    },
    {
      solution_name = "Security"
    }
  ]
  
  diagnostic_settings = [
    {
      name                       = "diag-law-monitoring"
      log_analytics_workspace_id = "self"
      enabled_log_categories     = ["Audit"]
      metric_categories          = ["AllMetrics"]
      log_retention_days         = 30
    }
  ]

  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
  }
}
```

## Examples

### Basic Development Workspace

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                = "law-monitoring-dev-eastus"
  resource_group_name = "rg-monitoring-dev-eastus"
  location            = "eastus"
  sku                 = "PerGB2018"
  retention_in_days   = 30
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Production Workspace with Solutions and Quotas

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                    = "law-monitoring-prod-eastus"
  resource_group_name     = "rg-monitoring-prod-eastus"
  location                = "eastus"
  sku                     = "PerGB2018"
  retention_in_days       = 90
  daily_quota_gb          = 100
  internet_ingestion_enabled = true
  internet_query_enabled     = true

  solution_plans = [
    {
      solution_name = "ContainerInsights"
    },
    {
      solution_name = "Security"
    },
    {
      solution_name = "ServiceMap"
    },
    {
      solution_name = "NetworkMonitoring"
    }
  ]
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
    CostCenter  = "Platform"
  }
}
```

### Workspace with Private Access Configuration

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                    = "law-monitoring-prod-eastus"
  resource_group_name     = "rg-monitoring-prod-eastus"
  location                = "eastus"
  sku                     = "PerGB2018"
  retention_in_days       = 90
  
  # Restrict to private network only
  internet_ingestion_enabled = false
  internet_query_enabled     = false
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Security    = "High"
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
| name | The name of the Log Analytics Workspace | `string` |
| resource_group_name | The name of the resource group where the workspace will be created | `string` |
| location | The Azure region where the workspace will be created | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| sku | The SKU of the workspace (Free, PerGB2018, Premium, Standard, Standalone, Unlimited, CapacityReservation) | `string` | `"PerGB2018"` | no |
| retention_in_days | The number of days to retain logs (30-730) | `number` | `30` | no |
| daily_quota_gb | The daily data ingestion quota in GB | `number` | `null` | no |
| internet_ingestion_enabled | Whether to enable internet ingestion | `bool` | `true` | no |
| internet_query_enabled | Whether to enable internet query | `bool` | `true` | no |
| solution_plans | A list of solution plans to install | `list(object)` | `[]` | no |
| diagnostic_settings | A list of diagnostic settings for the workspace | `list(object)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Log Analytics Workspace |
| name | The name of the Log Analytics Workspace |
| primary_shared_key | The primary shared key (sensitive) |
| secondary_shared_key | The secondary shared key (sensitive) |
| workspace_id | The workspace ID |
| solutions | The list of installed solutions |

## Module Resources

This module creates the following resources:
- Azure Log Analytics Workspace
- Log Analytics Solutions (optional)
- Diagnostic Settings (optional)

## Dependencies

This module has no dependencies on other modules.

## Integration with Other Services

### AKS Integration

To connect the Log Analytics Workspace to your AKS cluster:

```hcl
module "aks" {
  source = "../../modules/azure/aks_core"
  
  # ... other configuration ...
  
  log_analytics_workspace_id = module.log_analytics.id
  
  diagnostic_settings = [{
    name                       = "aks-diag"
    log_analytics_workspace_id = module.log_analytics.id
    enabled_log_categories     = ["kube-apiserver", "kube-audit", "kube-controller-manager"]
    metric_categories          = ["AllMetrics"]
    log_retention_days         = 30
  }]
}
```

### Virtual Machine Monitoring

To enable VM insights:

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  # ... basic configuration ...

  solution_plans = [
    {
      solution_name = "VMInsights"
    }
  ]
}
```

## Solution Pack Information

| Solution Name | Description |
|---------------|-------------|
| ContainerInsights | Monitoring solution for AKS and containers |
| Security | Security and compliance monitoring |
| ServiceMap | Service dependency mapping |
| VMInsights | Virtual machine performance and dependency monitoring |
| NetworkMonitoring | Network traffic and connection monitoring |
| KeyVaultAnalytics | Azure Key Vault monitoring |
| Updates | System update assessment and management |

## Notes

- The recommended SKU for production is `PerGB2018`
- Log retention must be between 30 and 730 days
- For high-security environments, consider disabling internet ingestion and query
- Daily quota helps control costs but may result in data loss if exceeded
- Each solution pack increases the cost of the workspace based on data ingestion
- For cost-effective monitoring, focus on relevant logs and metrics

## License

This module is licensed under the MIT License. 