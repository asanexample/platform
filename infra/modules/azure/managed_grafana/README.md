# Azure Managed Grafana Module

## Overview

This module creates an Azure Managed Grafana instance, providing a fully managed service for data visualization and analytics. It integrates with Azure Monitor, Prometheus workspaces, and Microsoft Entra ID (Azure AD) for authentication and authorization.

## Features

- Creates an Azure Managed Grafana dashboard instance with configurable settings
- Configures identity with System Assigned Managed Identity
- Integrates with Azure Monitor Prometheus workspaces
- Supports Microsoft Entra ID (Azure AD) group and user role assignments
- Controls security features including API keys and public network access
- Configurable Grafana version and zone redundancy options
- Supports consistent tagging and naming conventions

## Usage

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                = "grafana-monitoring-prod-eastus"
  resource_group_name = "rg-monitoring-prod-eastus"
  location            = "eastus"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
  }
}
```

## Examples

### Basic Development Grafana Instance

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                = "grafana-monitoring-dev-eastus"
  resource_group_name = "rg-monitoring-dev-eastus"
  location            = "eastus"
  
  # Development settings
  api_key_enabled               = true
  public_network_access_enabled = true
  zone_redundancy_enabled       = false
  grafana_major_version         = "10"
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Production with Prometheus Integration and Access Control

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                = "grafana-monitoring-prod-eastus"
  resource_group_name = "rg-monitoring-prod-eastus"
  location            = "eastus"
  
  # Integration with Azure Monitor Prometheus
  azure_monitor_workspace_integrations = [
    {
      workspace_id = module.monitor_workspace.id
    }
  ]
  
  # Microsoft Entra ID integration for access control
  admin_group_object_ids = [
    "11111111-1111-1111-1111-111111111111",  # Monitoring Admins Group
  ]
  
  admin_user_object_ids = [
    "22222222-2222-2222-2222-222222222222",  # DevOps Admin User
  ]
  
  # Production security settings
  api_key_enabled               = false
  public_network_access_enabled = true
  zone_redundancy_enabled       = true
  grafana_major_version         = "10"
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
    CostCenter  = "Platform"
  }
}
```

### Enhanced Security with Private Access

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                = "grafana-monitoring-prod-eastus"
  resource_group_name = "rg-monitoring-prod-eastus"
  location            = "eastus"
  
  # Security settings
  api_key_enabled               = false
  public_network_access_enabled = false  # Restrict to private endpoints only
  deterministic_outbound_ip_enabled = true
  zone_redundancy_enabled       = true
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "Monitoring"
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
| name | The name of the Azure Managed Grafana instance | `string` |
| resource_group_name | The name of the resource group where the Grafana instance will be created | `string` |
| location | The Azure region where the Grafana instance will be created | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| azure_monitor_workspace_integrations | List of Azure Monitor workspace integrations | `list(object)` | `[]` | no |
| api_key_enabled | Whether to enable API key authentication for the Grafana instance | `bool` | `true` | no |
| deterministic_outbound_ip_enabled | Whether to enable deterministic outbound IPs for the Grafana instance | `bool` | `false` | no |
| public_network_access_enabled | Whether to enable public network access for the Grafana instance | `bool` | `true` | no |
| zone_redundancy_enabled | Whether to enable zone redundancy for the Grafana instance | `bool` | `true` | no |
| grafana_major_version | The major version of Grafana to use (must be "9" or "10") | `string` | `"9"` | no |
| auto_generated_domain_name_label_scope | The scope for the auto-generated domain name label | `string` | `"TenantReuse"` | no |
| admin_group_object_ids | List of Microsoft Entra group Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| admin_user_object_ids | List of Microsoft Entra user Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Managed Grafana instance |
| name | The name of the Azure Managed Grafana instance |
| resource_group_name | The name of the resource group where the Grafana instance is deployed |
| endpoint | The endpoint URL of the Azure Managed Grafana instance |
| grafana_version | The version of Grafana being used |
| identity | The identity of the Azure Managed Grafana instance |

## Module Resources

This module creates the following resources:
- Azure Managed Grafana instance
- Microsoft Entra ID (Azure AD) role assignments (when configured)

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation
- [monitor_workspace](../monitor_workspace) - For Prometheus integration

## Microsoft Entra ID Integration

Azure Managed Grafana uses Microsoft Entra ID for authentication and authorization. This module allows you to configure:

1. **Admin Groups**: Microsoft Entra ID groups that will have administrator privileges in Grafana
2. **Admin Users**: Microsoft Entra ID users that will have administrator privileges in Grafana

The module automatically assigns the appropriate roles using the provided Object IDs.

## Azure Monitor Integration

Azure Managed Grafana can be integrated with Azure Monitor workspaces to visualize metrics from:

- Azure Monitor metrics
- Azure Monitor Log Analytics
- Azure Monitor Prometheus

This integration enables native querying of these data sources without additional configuration.

## Notes

- Azure Managed Grafana is a managed service, so you do not need to manage the underlying infrastructure
- For high availability in production, enable zone redundancy
- API keys should be disabled in production environments for enhanced security
- When integrating with Azure Monitor, ensure the Grafana instance has the appropriate permissions
- The Grafana major version determines which features are available
- The endpoint URL is used to access the Grafana dashboard
- Consider using private endpoints for enhanced security in production environments

## License

This module is licensed under the MIT License. 