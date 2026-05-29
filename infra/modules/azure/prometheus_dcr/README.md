# Prometheus DCR

Creates an Azure Monitor Data Collection Rule (DCR) and Data Collection Endpoint (DCE) configured for Prometheus metrics scraping from AKS clusters. The DCR defines a Prometheus forwarder data source that streams `Microsoft-PrometheusMetrics` to an Azure Monitor workspace. The DCE provides the ingestion endpoint. Both resources are set to `kind = "Linux"` as required for Prometheus collection.

## Usage

```hcl
module "prometheus_dcr" {
  source = "../../modules/azure/prometheus_dcr"

  resource_group_name  = "rg-platform-dev-eus"
  location             = "eastus"
  monitor_workspace_id = "/subscriptions/.../providers/Microsoft.Monitor/accounts/amw-platform-dev-eus-prometheus"

  name     = "dcr-prometheus-eastus"
  dce_name = "dce-prometheus-eastus"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "prometheus_dcr" {
  source = "../../modules/azure/prometheus_dcr"
  create = false
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_monitor_data_collection_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_endpoint) | resource |
| [azurerm_monitor_data_collection_rule.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_data_collection_rule) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | The Azure region where the DCR and DCE will be deployed. | `string` | n/a | yes |
| <a name="input_monitor_workspace_id"></a> [monitor\_workspace\_id](#input\_monitor\_workspace\_id) | The resource ID of the Azure Monitor Workspace to send metrics to. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group to deploy the DCR and DCE in. | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_dce_name"></a> [dce\_name](#input\_dce\_name) | Optional name for the Data Collection Endpoint (DCE). Defaults will be generated if null. | `string` | `null` | no |
| <a name="input_name"></a> [name](#input\_name) | Optional base name for the DCR (e.g., 'dcr-prometheus'). Defaults will be generated if null. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to apply to the DCR and DCE. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_dce_id"></a> [dce\_id](#output\_dce\_id) | The ID of the created Data Collection Endpoint. |
| <a name="output_dce_name"></a> [dce\_name](#output\_dce\_name) | The name of the created Data Collection Endpoint. |
| <a name="output_dcr_id"></a> [dcr\_id](#output\_dcr\_id) | The ID of the created Data Collection Rule. |
| <a name="output_dcr_name"></a> [dcr\_name](#output\_dcr\_name) | The name of the created Data Collection Rule. |
<!-- END_TF_DOCS -->

## Notes

- The `monitor_workspace_id` must point to an existing Azure Monitor workspace (created via the `monitor_workspace` module). The DCR routes all Prometheus metrics to this workspace.
- The DCR ID output (`dcr_id`) is passed to the `aks_core` module's `prometheus_dcr_id` variable to associate the AKS cluster with the data collection rule.
- Names default to `dcr-prometheus-{location}` and `dce-prometheus-{location}` if not explicitly provided.
- Both DCR and DCE must be in the same Azure region as the AKS cluster they collect metrics from.
