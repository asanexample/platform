# Front Door Endpoint

Creates an Azure Front Door endpoint and origin group within an existing Front Door profile. The endpoint is the public-facing entry point for traffic, and the origin group defines how origins are load-balanced and health-checked. Origins and routes are added separately via the `frontdoor_private_link` module or direct resource declarations. The profile can be referenced by ID or looked up by name and resource group.

## Usage

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  profile_id       = "/subscriptions/.../profiles/fd-platform-dev-eus"
  endpoint_name    = "fde-platform-dev-eus"
  origin_group_name = "fdog-platform-dev-eus"

  health_probe_enabled = true
  health_probe_settings = {
    protocol            = "Https"
    interval_in_seconds = 60
    path                = "/health"
    request_type        = "GET"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"
  create = false
}
```

### Lookup Profile by Name

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  profile_name                = "fd-platform-dev-eus"
  profile_resource_group_name = "rg-platform-dev-eus"
  endpoint_name               = "fde-platform-dev-eus"
  origin_group_name           = "fdog-platform-dev-eus"

  load_balancing_enabled = true
  load_balancing_settings = {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
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
| [azurerm_cdn_frontdoor_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_endpoint) | resource |
| [azurerm_cdn_frontdoor_origin_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_origin_group) | resource |
| [azurerm_cdn_frontdoor_profile.profile](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/cdn_frontdoor_profile) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_endpoint_name"></a> [endpoint\_name](#input\_endpoint\_name) | The name of the Front Door endpoint | `string` | n/a | yes |
| <a name="input_origin_group_name"></a> [origin\_group\_name](#input\_origin\_group\_name) | The name of the origin group | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Controls whether the Front Door endpoint resources are deployed | `bool` | `true` | no |
| <a name="input_health_probe_enabled"></a> [health\_probe\_enabled](#input\_health\_probe\_enabled) | Whether to enable health probe | `bool` | `false` | no |
| <a name="input_health_probe_settings"></a> [health\_probe\_settings](#input\_health\_probe\_settings) | Health probe settings for the origin group | <pre>object({<br/>    protocol            = optional(string, "Http")<br/>    interval_in_seconds = optional(number, 120)<br/>    path                = optional(string, "/")<br/>    request_type        = optional(string, "HEAD")<br/>  })</pre> | <pre>{<br/>  "interval_in_seconds": 120,<br/>  "path": "/",<br/>  "protocol": "Http",<br/>  "request_type": "HEAD"<br/>}</pre> | no |
| <a name="input_load_balancing_enabled"></a> [load\_balancing\_enabled](#input\_load\_balancing\_enabled) | Whether to enable custom load balancing settings | `bool` | `false` | no |
| <a name="input_load_balancing_settings"></a> [load\_balancing\_settings](#input\_load\_balancing\_settings) | Load balancing settings for the origin group | <pre>object({<br/>    additional_latency_in_milliseconds = optional(number)<br/>    sample_size                        = optional(number)<br/>    successful_samples_required        = optional(number)<br/>  })</pre> | <pre>{<br/>  "additional_latency_in_milliseconds": null,<br/>  "sample_size": null,<br/>  "successful_samples_required": null<br/>}</pre> | no |
| <a name="input_profile_id"></a> [profile\_id](#input\_profile\_id) | The ID of the Front Door profile. If provided, profile\_name and profile\_resource\_group\_name are not required. | `string` | `null` | no |
| <a name="input_profile_name"></a> [profile\_name](#input\_profile\_name) | The name of the Front Door profile. Required if profile\_id is not provided. | `string` | `null` | no |
| <a name="input_profile_resource_group_name"></a> [profile\_resource\_group\_name](#input\_profile\_resource\_group\_name) | The name of the resource group containing the Front Door profile. Required if profile\_id is not provided. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether the Front Door endpoint is created |
| <a name="output_endpoint_host_name"></a> [endpoint\_host\_name](#output\_endpoint\_host\_name) | The host name of the Front Door endpoint |
| <a name="output_endpoint_id"></a> [endpoint\_id](#output\_endpoint\_id) | The ID of the Front Door endpoint |
| <a name="output_endpoint_name"></a> [endpoint\_name](#output\_endpoint\_name) | The name of the Front Door endpoint |
| <a name="output_origin_group_id"></a> [origin\_group\_id](#output\_origin\_group\_id) | The ID of the origin group |
| <a name="output_origin_group_name"></a> [origin\_group\_name](#output\_origin\_group\_name) | The name of the origin group |
<!-- END_TF_DOCS -->

## Notes

- Either `profile_id` or the combination of `profile_name` and `profile_resource_group_name` must be provided. If `profile_id` is set, the data source lookup is skipped.
- Health probes and custom load balancing settings are disabled by default. Enable them with `health_probe_enabled` and `load_balancing_enabled` respectively.
- This module does not create origins or routes. Use `frontdoor_private_link` or additional resources to attach origins to the origin group.
