# Resource Group

Creates an Azure resource group, which is the logical container for all other Azure resources in a deployment. This is typically the first module deployed in any environment stack. The resource group name is usually provided by Terragrunt via the `naming` module.

## Usage

```hcl
module "resource_group" {
  source = "../../modules/azure/resource_group"

  name     = "rg-platform-dev-eus"
  location = "eastus"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "resource_group" {
  source = "../../modules/azure/resource_group"
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
| [azurerm_resource_group.rg](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/resource_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | Azure region where the resource group will be created | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| <a name="input_name"></a> [name](#input\_name) | Name of the resource group. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to the resource group | `map(string)` | `{}` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_id"></a> [id](#output\_id) | The ID of the resource group |
| <a name="output_location"></a> [location](#output\_location) | The location of the resource group |
| <a name="output_name"></a> [name](#output\_name) | The name of the resource group |
<!-- END_TF_DOCS -->

## Notes

- Resource group names must be 1-90 characters and can include alphanumeric, hyphen, underscore, parentheses, and period characters.
- The `name` variable accepts null, in which case Terragrunt is expected to supply the name via the naming module.
- Outputs include `name`, `id`, and `location`, which are consumed by virtually all downstream modules as required inputs.
