# Azure Log Analytics Module

This module provisions an Azure Log Analytics workspace with configurable settings, solution packs, and diagnostic configurations. It's designed to be a central component for monitoring and diagnostics across Azure resources, with particular focus on AKS monitoring.

## Features

- Creates a Log Analytics workspace with customizable retention and SKU
- Supports adding multiple solution packs (e.g., ContainerInsights, Security)
- Configures diagnostic settings for the workspace
- Enables linked storage accounts for long-term log storage
- Supports various network access controls

## Usage

```hcl
module "log_analytics" {
  source = "../../modules/azure/log_analytics"
  
  # Resource details
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  # Naming convention variables (will generate: centric-dev-law-eus)
  prefix      = "centric"
  environment = "dev"
  region_abbv = "eus"
  
  # Or provide explicit name
  # name       = "law-dev-eastus-001"
  
  # Workspace Configuration
  sku                 = "PerGB2018"
  retention_in_days   = 30
  daily_quota_gb      = 5
  
  # Solution packs
  solution_plans = [
    {
      solution_name = "ContainerInsights"
    },
    {
      solution_name = "Security"
    },
    {
      solution_name = "AzureActivity"
    }
  ]
  
  # Diagnostic settings
  diagnostic_settings = [
    {
      name                       = "law-diag"
      log_analytics_workspace_id = "self"  # Send logs to itself
      enabled_log_categories     = ["Audit"]
      metric_categories          = ["AllMetrics"]
      log_retention_days         = 30
    }
  ]
  
  # Tags
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## AKS Integration Example

This module is particularly useful for AKS monitoring:

```hcl
# Create Log Analytics workspace
module "log_analytics" {
  source = "../../modules/azure/log_analytics"
  
  name                = "law-aks-monitoring"
  resource_group_name = azurerm_resource_group.example.name
  location            = azurerm_resource_group.example.location
  
  solution_plans = [
    {
      solution_name = "ContainerInsights"
    }
  ]
}

# Create AKS cluster with Log Analytics integration
module "aks" {
  source = "../../modules/azure/aks"
  
  # ... other AKS configuration ...
  
  # Enable monitoring with Log Analytics
  enable_log_analytics_workspace = true
  log_analytics_workspace_id     = module.log_analytics.id
  
  # Configure diagnostic settings
  diagnostic_settings = [
    {
      name                       = "aks-diag"
      log_analytics_workspace_id = module.log_analytics.id
      enabled_log_categories     = [
        "kube-apiserver",
        "kube-audit",
        "kube-controller-manager",
        "kube-scheduler",
        "cluster-autoscaler"
      ]
      metric_categories = ["AllMetrics"]
      log_retention_days = 30
    }
  ]
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | The prefix to use for generated resource names | `string` | `"centric"` | no |
| customer | The customer identifier | `string` | `null` | no |
| environment | The environment (e.g., dev, test, prod) | `string` | `"dev"` | no |
| region_abbv | The abbreviated region name | `string` | `"weu"` | no |
| name | The name of the Log Analytics workspace | `string` | n/a | no |
| resource_group_name | The name of the resource group | `string` | n/a | yes |
| location | The Azure region where resources will be created | `string` | n/a | yes |
| sku | The SKU of the Log Analytics workspace | `string` | `"PerGB2018"` | no |
| retention_in_days | The number of days to retain data (30-730) | `number` | `30` | no |
| daily_quota_gb | The daily ingestion quota in GB | `number` | `null` | no |
| internet_ingestion_enabled | Whether internet ingestion is enabled | `bool` | `true` | no |
| internet_query_enabled | Whether internet query is enabled | `bool` | `true` | no |
| reservation_capacity_in_gb_per_day | Capacity reservation level in GB per day | `number` | `0` | no |
| solution_plans | List of solution plans to deploy | `list(object({solution_name=string}))` | `[]` | no |
| diagnostic_settings | List of diagnostic settings to create | `list(object({...}))` | `[]` | no |
| linked_storage_accounts | Map of data source types to storage account IDs | `map(list(string))` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Log Analytics workspace |
| name | The name of the Log Analytics workspace |
| primary_shared_key | The primary shared key (sensitive) |
| secondary_shared_key | The secondary shared key (sensitive) |
| workspace_id | The workspace ID |
| solution_ids | The IDs of the deployed Log Analytics solutions |
| diagnostic_settings | The diagnostic settings created |
| linked_storage_accounts | The linked storage accounts |

## Solution Packs Reference

Common solution packs that can be deployed:

| Solution Name | Description |
|---------------|-------------|
| ContainerInsights | For AKS and container monitoring |
| Security | For security monitoring |
| AzureActivity | For Azure Activity logs |
| SQLAssessment | For SQL Server assessment |
| Updates | For update management |
| VMInsights | For virtual machine monitoring |
| ServiceMap | For service dependency mapping |
| KeyVaultAnalytics | For Key Vault monitoring |
| AzureAppGatewayAnalytics | For Application Gateway monitoring |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.23.0 |

## Notes

- For the SKU `CapacityReservation`, you must specify `reservation_capacity_in_gb_per_day`
- Log Analytics pricing is based on data ingestion, so monitor your usage to control costs
- By specifying `"self"` as the `log_analytics_workspace_id` in diagnostic settings, logs will be sent to the workspace itself

## License

This module is licensed under the MIT License. 