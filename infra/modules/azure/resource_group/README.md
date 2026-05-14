# Azure Resource Group Module

Creates an Azure resource group — the foundational container for all other Azure resources in a region.

## Usage

```hcl
module "resource_group" {
  source = "../resource_group"

  create   = true
  name     = "rg-platform-dev-eus"
  location = "eastus"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "resource_group" {
  source = "../resource_group"
  create = false
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| location | Azure region where the resource group will be created | `string` | n/a | yes |
| create | Whether to create resources in this module | `bool` | `true` | no |
| environment | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| name | Name of the resource group. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| workload | Workload name for resource names | `string` | `"platform"` | no |
| region_abbv | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| tags | Tags to apply to the resource group | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| id | The ID of the resource group |
| location | The location of the resource group |
| name | The name of the resource group |
<!-- END_TF_DOCS -->

## Dependencies

None — this is a foundational module that other modules depend on.

## Notes

- Resource group deletion cascades to all resources inside it.
- Names must be unique within a subscription and are validated against Azure naming rules (1-90 chars, alphanumeric/hyphen/underscore/parentheses/period).
