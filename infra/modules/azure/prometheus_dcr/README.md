# Azure Prometheus DCR Module

Creates a data collection endpoint (DCE) and data collection rule (DCR) for scraping Prometheus metrics from AKS clusters into an Azure Monitor workspace.

## Usage

```hcl
module "prometheus_dcr" {
  source = "../prometheus_dcr"

  create = true

  resource_group_name  = "rg-platform-prod-eus"
  location             = "eastus"
  monitor_workspace_id = module.monitor_workspace.id
  name                 = "dcr-platform-prometheus-prod"
  dce_name             = "dce-platform-prometheus-prod"

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "prometheus_dcr" {
  source = "../prometheus_dcr"
  create = false
}
```

### Auto-generated names

```hcl
module "prometheus_dcr" {
  source = "../prometheus_dcr"

  create = true

  resource_group_name  = "rg-platform-dev-eus"
  location             = "eastus"
  monitor_workspace_id = module.monitor_workspace.id

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_monitor_data_collection_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_endpoint) | resource |
| [azurerm_monitor_data_collection_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | The Azure region where the DCR and DCE will be deployed. | `string` | n/a | yes |
| monitor_workspace_id | The resource ID of the Azure Monitor Workspace to send metrics to. | `string` | n/a | yes |
| resource_group_name | The name of the resource group to deploy the DCR and DCE in. | `string` | n/a | yes |
| create | Whether to create resources in this module | `bool` | `true` | no |
| dce_name | Optional name for the Data Collection Endpoint (DCE). Defaults will be generated if null. | `string` | `null` | no |
| name | Optional base name for the DCR (e.g., 'dcr-prometheus'). Defaults will be generated if null. | `string` | `null` | no |
| tags | A map of tags to apply to the DCR and DCE. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| dce_id | The ID of the created Data Collection Endpoint. |
| dce_name | The name of the created Data Collection Endpoint. |
| dcr_id | The ID of the created Data Collection Rule. |
| dcr_name | The name of the created Data Collection Rule. |
<!-- END_TF_DOCS -->

## Dependencies

- [monitor_workspace](../monitor_workspace) — Provides the Azure Monitor workspace ID to send metrics to
- [aks_core](../aks_core) — The DCR must be associated with an AKS cluster via `azurerm_monitor_data_collection_rule_association`

## Notes

- DCR and DCE are region-specific; create separate instances per region in multi-region deployments.
- Default names are generated from the location if `name` and `dce_name` are null.
- The AKS cluster association is not handled by this module; use `azurerm_monitor_data_collection_rule_association` to link the DCR to your cluster.
