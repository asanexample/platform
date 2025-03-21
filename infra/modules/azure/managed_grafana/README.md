# Azure Managed Grafana Module

## Overview

This module creates an Azure Managed Grafana instance and configures it to work with Azure Managed Prometheus for comprehensive monitoring and visualization capabilities. It includes role assignments for administrators and integration with Azure Monitor workspaces.

## Features

- Creates an Azure Managed Grafana instance with configurable settings
- Automatically integrates with Azure Managed Prometheus (Azure Monitor workspace)
- Assigns Grafana Admin role to the deploying user
- Supports additional admin assignments for both Azure AD groups and users
- Configures security, performance, and availability options
- Enables system-assigned managed identity for access to Azure resources

## Usage

### Basic Usage

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                  = "monitoring-grafana"
  resource_group_name   = "monitoring-rg"
  location              = "eastus"
  prometheus_workspace_id = module.prometheus.id  # ID of an Azure Monitor workspace
  
  tags = {
    environment = "production"
    application = "monitoring-stack"
    owner       = "platform-team"
  }
}
```

### Advanced Usage with Custom Settings

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                  = "secure-grafana"
  resource_group_name   = "monitoring-rg"
  location              = "eastus"
  prometheus_workspace_id = module.prometheus.id
  
  # Security settings
  api_key_enabled                = false
  public_network_access_enabled  = false
  
  # High availability settings
  deterministic_outbound_ip_enabled = true
  zone_redundancy_enabled        = true
  
  # Version control
  grafana_major_version          = "10"
  
  # Admin access
  admin_group_object_ids         = ["00000000-0000-0000-0000-000000000001"]
  admin_user_object_ids          = ["00000000-0000-0000-0000-000000000002"]
  
  tags = {
    environment = "production"
    application = "monitoring-stack"
    owner       = "platform-team"
  }
}
```

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| name | Name of the Azure Managed Grafana instance | string |
| resource_group_name | Name of the resource group in which to create the Grafana instance | string |
| location | Azure region where the Grafana instance should be created | string |
| prometheus_workspace_id | Resource ID of the Azure Monitor workspace (Managed Prometheus) | string |

## Optional Inputs

| Name | Description | Type | Default |
|------|-------------|------|---------|
| api_key_enabled | Enable the API key mechanism in Grafana | bool | true |
| deterministic_outbound_ip_enabled | Whether to enable deterministic outbound IPs | bool | true |
| public_network_access_enabled | Whether to enable public network access | bool | true |
| zone_redundancy_enabled | Whether to enable zone redundancy | bool | true |
| grafana_major_version | The major version of Grafana to deploy | string | "10" |
| admin_group_object_ids | Azure AD group object IDs for Grafana Admin role | list(string) | [] |
| admin_user_object_ids | Azure AD user object IDs for Grafana Admin role | list(string) | [] |
| tags | Tags to apply to the resource | map(string) | {} |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Managed Grafana instance |
| name | The name of the Azure Managed Grafana instance |
| endpoint | The endpoint URL of the Azure Managed Grafana instance |
| principal_id | The principal ID of the system assigned identity |

## Notes

- Azure Managed Grafana automatically integrates with Azure AD for authentication
- The current deploying identity automatically receives the Grafana Admin role
- By default, public access is enabled - disable for production environments with sensitive data
- Use deterministic outbound IPs when connecting to resources behind firewalls
- The Grafana instance receives a system-assigned managed identity that can be used for accessing Azure resources
- Zone redundancy is recommended for production environments 