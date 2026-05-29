# Monitor Workspace

Creates an Azure Monitor workspace, which serves as the storage and query backend for Azure Managed Prometheus metrics. This is a lightweight wrapper around `azurerm_monitor_workspace` that provides the workspace ID and query endpoint consumed by the `prometheus_dcr` and `managed_grafana` modules.

## Usage

```hcl
module "monitor_workspace" {
  source = "../../modules/azure/monitor_workspace"

  name                = "amw-platform-dev-eus-prometheus"
  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "monitor_workspace" {
  source = "../../modules/azure/monitor_workspace"
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
| [azurerm_monitor_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_workspace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | The Azure region where the Azure Monitor Workspace will be deployed. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group to deploy the Azure Monitor Workspace in. | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the Azure Monitor Workspace. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A map of tags to apply to the Azure Monitor Workspace. | `map(string)` | `{}` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_id"></a> [id](#output\_id) | The ID of the Azure Monitor Workspace. |
| <a name="output_name"></a> [name](#output\_name) | The name of the Azure Monitor Workspace. |
| <a name="output_query_endpoint"></a> [query\_endpoint](#output\_query\_endpoint) | The query endpoint for the Azure Monitor Workspace. |
<!-- END_TF_DOCS -->

## Notes

- The workspace ID output is required by the `prometheus_dcr` module (for the data collection rule destination) and the `managed_grafana` module (for Prometheus integration).
- The `query_endpoint` output provides the PromQL query URL used by Grafana and other consumers.
- Azure Monitor workspace names must be 3-90 characters, alphanumeric with hyphens and underscores.
