# Azure Monitor Workspace Module

Creates an Azure Monitor workspace for storing Prometheus metrics from AKS clusters and other sources.

## Usage

```hcl
module "monitor_workspace" {
  source = "../monitor_workspace"

  create = true

  resource_group_name = "rg-platform-prod-eus"
  location            = "eastus"
  name                = "mw-platform-prod-eus"

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "monitor_workspace" {
  source = "../monitor_workspace"
  create = false
}
```

### Auto-generated name via naming module

```hcl
module "monitor_workspace" {
  source = "../monitor_workspace"

  create = true

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"

  workload    = "platform"
  environment = "dev"
  region_abbv = "eus"

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
| [azurerm_monitor_workspace.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/monitor_workspace) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | The Azure region where the Azure Monitor Workspace will be deployed. | `string` | n/a | yes |
| resource_group_name | The name of the resource group to deploy the Azure Monitor Workspace in. | `string` | n/a | yes |
| create | Whether to create resources in this module | `bool` | `true` | no |
| environment | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| name | The name of the Azure Monitor Workspace. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| workload | Workload name for resource names | `string` | `"platform"` | no |
| region_abbv | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| tags | A map of tags to apply to the Azure Monitor Workspace. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| id | The ID of the Azure Monitor Workspace. |
| name | The name of the Azure Monitor Workspace. |
| query_endpoint | The query endpoint for the Azure Monitor Workspace. |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) — Provides standardized resource names
- [resource_group](../resource_group) — Provides the resource group to deploy into

## Notes

- Monitor Workspaces have a fixed 30-day retention period; plan archival separately.
- Deploy in the same region as monitored resources to minimize metric collection latency.
- Pricing is separate from Log Analytics Workspaces.
