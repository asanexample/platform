# Front Door Profile

Creates an Azure Front Door profile, which is the top-level parent resource for all Front Door endpoints, origin groups, origins, and routes. The profile defines the SKU tier (Standard or Premium) and optional response timeout. Endpoints and origins are created separately via the `frontdoor_endpoint` and `frontdoor_private_link` modules.

## Usage

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                = "fd-platform-dev-eus"
  resource_group_name = "rg-platform-dev-eus"
  sku_name            = "Standard_AzureFrontDoor"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"
  create = false
}
```

### Premium SKU with Custom Timeout

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                     = "fd-platform-prod-eus"
  resource_group_name      = "rg-platform-prod-eus"
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = 120

  tags = {
    Environment = "prod"
  }
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
| [azurerm_cdn_frontdoor_profile.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_profile) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group in which to create the Front Door profile | `string` | n/a | yes |
| <a name="input_sku_name"></a> [sku\_name](#input\_sku\_name) | The SKU name of the Front Door profile (Standard\_AzureFrontDoor or Premium\_AzureFrontDoor) | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether the Front Door profile is deployed | `bool` | `true` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the Front Door profile. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| <a name="input_response_timeout_seconds"></a> [response\_timeout\_seconds](#input\_response\_timeout\_seconds) | Response timeout in seconds. Possible values are between 16 and 240 seconds (inclusive) | `number` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the resource | `map(string)` | `{}` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | `"platform"` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether the Front Door profile is created |
| <a name="output_id"></a> [id](#output\_id) | The ID of the Front Door profile |
| <a name="output_name"></a> [name](#output\_name) | The name of the Front Door profile |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group where the Front Door profile exists |
| <a name="output_sku_name"></a> [sku\_name](#output\_sku\_name) | The SKU name of the Front Door profile |
<!-- END_TF_DOCS -->

## Notes

- Premium SKU is required for Private Link origins, WAF with managed rules, and bot protection. Standard is sufficient for basic CDN and routing.
- The `response_timeout_seconds` must be between 16 and 240 seconds. If not set, Azure uses its default.
- The profile name can be null if Terragrunt supplies it via the naming module.
