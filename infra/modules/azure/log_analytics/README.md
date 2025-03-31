# Azure Log Analytics Workspace Module

This module creates an Azure Log Analytics Workspace with essential configurations for monitoring Azure Kubernetes Service (AKS) clusters.

## Features

- Creates a Log Analytics Workspace with configurable retention and settings
- Supports installation of solution packs (ContainerInsights, Security, etc.)
- Configures diagnostic settings for the workspace itself
- Provides all necessary outputs for integration with other services

## Usage

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"

  name                = "vip-dev-law-eus"
  resource_group_name = "vip-dev-rg-eus"
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
      name                       = "vip-dev-law-eus-diag"
      log_analytics_workspace_id = "self"
      enabled_log_categories     = ["Audit"]
      metric_categories          = ["AllMetrics"]
      log_retention_days         = 30
    }
  ]

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| name | The name of the Log Analytics Workspace | `string` | n/a | yes |
| resource_group_name | The name of the resource group where the workspace will be created | `string` | n/a | yes |
| location | The Azure region where the workspace will be created | `string` | n/a | yes |
| sku | The SKU of the workspace | `string` | `"PerGB2018"` | no |
| retention_in_days | The number of days to retain logs | `number` | `30` | no |
| daily_quota_gb | The daily data ingestion quota in GB | `number` | `null` | no |
| internet_ingestion_enabled | Whether to enable internet ingestion | `bool` | `true` | no |
| internet_query_enabled | Whether to enable internet query | `bool` | `true` | no |
| solution_plans | A list of solution plans to install | `list(object)` | `[]` | no |
| diagnostic_settings | A list of diagnostic settings for the workspace | `list(object)` | `[]` | no |
| tags | A map of tags to apply to resources | `map(string)` | `{}` | no |

## Output Values

| Name | Description |
|------|-------------|
| id | The ID of the Log Analytics Workspace |
| name | The name of the Log Analytics Workspace |
| primary_shared_key | The primary shared key (sensitive) |
| secondary_shared_key | The secondary shared key (sensitive) |
| workspace_id | The workspace ID |
| solutions | The list of installed solutions |

## Integration with AKS

To connect the Log Analytics Workspace to your AKS cluster, reference the workspace ID in your AKS cluster configuration:

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