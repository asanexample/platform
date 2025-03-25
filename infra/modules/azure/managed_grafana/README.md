# Azure Managed Grafana Module

This Terraform module deploys an Azure Managed Grafana instance with Microsoft Entra (Azure AD) integration and Prometheus workspace connections.

## Features

- Creates an Azure Managed Grafana dashboard instance
- Configures identity with System Assigned Managed Identity
- Integrates with Azure Monitor Prometheus workspaces
- Allows for Microsoft Entra (Azure AD) group and user role assignments
- Supports configuration of security settings (API keys, public network access)
- Configurable Grafana version and redundancy options

## Usage

### Basic Usage

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                = "my-grafana-dashboard"
  resource_group_name = "rg-monitoring"
  location            = "eastus"
}
```

### Usage with Prometheus Integration

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                    = "my-grafana-dashboard"
  resource_group_name     = "rg-monitoring"
  location                = "eastus"
  prometheus_workspace_id = azurerm_monitor_workspace.prometheus.id
}
```

### Advanced Usage with Admin Assignments

```hcl
module "grafana" {
  source = "../../modules/azure/managed_grafana"

  name                    = "my-grafana-dashboard"
  resource_group_name     = "rg-monitoring"
  location                = "eastus"
  prometheus_workspace_id = azurerm_monitor_workspace.prometheus.id
  
  admin_group_object_ids = [
    "11111111-1111-1111-1111-111111111111",  # Monitoring Admins Group
  ]
  
  admin_user_object_ids = [
    "22222222-2222-2222-2222-222222222222",  # DevOps Admin User
  ]
  
  api_key_enabled               = false
  public_network_access_enabled = true
  zone_redundancy_enabled       = true
  grafana_major_version         = "10"
  
  tags = {
    Environment = "Production"
    CostCenter  = "IT"
  }
}
```

## Required Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the Azure Managed Grafana instance | `string` | n/a | yes |
| resource_group_name | The name of the resource group where the Grafana instance will be created | `string` | n/a | yes |
| location | The Azure region where the Grafana instance will be created | `string` | n/a | yes |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prometheus_workspace_id | The resource ID of the Azure Monitor workspace to integrate with Grafana | `string` | `null` | no |
| api_key_enabled | Whether to enable API key authentication for the Grafana instance | `bool` | `true` | no |
| deterministic_outbound_ip_enabled | Whether to enable deterministic outbound IPs for the Grafana instance | `bool` | `false` | no |
| public_network_access_enabled | Whether to enable public network access for the Grafana instance | `bool` | `true` | no |
| zone_redundancy_enabled | Whether to enable zone redundancy for the Grafana instance | `bool` | `true` | no |
| grafana_major_version | The major version of Grafana to use (must be "9" or "10") | `string` | `"9"` | no |
| auto_generated_domain_name_label_scope | The scope for the auto-generated domain name label | `string` | `"TenantReuse"` | no |
| admin_group_object_ids | List of Microsoft Entra group Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| admin_user_object_ids | List of Microsoft Entra user Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| tags | A mapping of tags to assign to the resource | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Azure Managed Grafana instance |
| name | The name of the Azure Managed Grafana instance |
| resource_group_name | The name of the resource group where the Grafana instance is deployed |
| endpoint | The endpoint URL of the Azure Managed Grafana instance |
| grafana_version | The version of Grafana being used |
| identity | The identity of the Azure Managed Grafana instance |

## License

This module is licensed under the MIT License - see the LICENSE file for details. 