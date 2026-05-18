# Azure Front Door Endpoint Module

Creates a Front Door endpoint and origin group within an existing Front Door profile.

## Usage

```hcl
module "frontdoor_endpoint" {
  source = "../frontdoor_endpoint"

  create            = true
  profile_id        = module.frontdoor_profile.id
  endpoint_name     = "web"
  origin_group_name = "origin-group-web"

  health_probe_enabled = true
  health_probe_settings = {
    protocol            = "Https"
    interval_in_seconds = 30
    path                = "/healthz"
    request_type        = "GET"
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "frontdoor_endpoint" {
  source = "../frontdoor_endpoint"

  create            = false
  endpoint_name     = "placeholder"
  origin_group_name = "placeholder"
}
```

### Lookup profile by name instead of ID

```hcl
module "frontdoor_endpoint" {
  source = "../frontdoor_endpoint"

  create                      = true
  profile_name                = "fd-platform-dev-eus"
  profile_resource_group_name = "rg-platform-dev-eus"
  endpoint_name               = "api"
  origin_group_name           = "origin-group-api"
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_cdn_frontdoor_endpoint.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_endpoint) | resource |
| [azurerm_cdn_frontdoor_origin_group.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_origin_group) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| endpoint_name | The name of the Front Door endpoint | `string` | n/a | yes |
| origin_group_name | The name of the origin group | `string` | n/a | yes |
| create | Controls whether the Front Door endpoint resources are deployed | `bool` | `true` | no |
| health_probe_enabled | Whether to enable health probe | `bool` | `false` | no |
| health_probe_settings | Health probe settings for the origin group | <pre>object({<br/>    protocol            = optional(string, "Http")<br/>    interval_in_seconds = optional(number, 120)<br/>    path                = optional(string, "/")<br/>    request_type        = optional(string, "HEAD")<br/>  })</pre> | <pre>{<br/>  "interval_in_seconds": 120,<br/>  "path": "/",<br/>  "protocol": "Http",<br/>  "request_type": "HEAD"<br/>}</pre> | no |
| load_balancing_enabled | Whether to enable custom load balancing settings | `bool` | `false` | no |
| load_balancing_settings | Load balancing settings for the origin group | <pre>object({<br/>    additional_latency_in_milliseconds = optional(number)<br/>    sample_size                        = optional(number)<br/>    successful_samples_required        = optional(number)<br/>  })</pre> | <pre>{<br/>  "additional_latency_in_milliseconds": null,<br/>  "sample_size": null,<br/>  "successful_samples_required": null<br/>}</pre> | no |
| profile_id | The ID of the Front Door profile. If provided, profile_name and profile_resource_group_name are not required. | `string` | `null` | no |
| profile_name | The name of the Front Door profile. Required if profile_id is not provided. | `string` | `null` | no |
| profile_resource_group_name | The name of the resource group containing the Front Door profile. Required if profile_id is not provided. | `string` | `null` | no |
| tags | A mapping of tags to assign to resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether the Front Door endpoint is created |
| endpoint_host_name | The host name of the Front Door endpoint |
| endpoint_id | The ID of the Front Door endpoint |
| endpoint_name | The name of the Front Door endpoint |
| origin_group_id | The ID of the origin group |
| origin_group_name | The name of the origin group |
<!-- END_TF_DOCS -->

## Dependencies

- [frontdoor_profile](../frontdoor_profile) -- the parent Front Door profile

## Notes

- Provide either `profile_id` or both `profile_name` and `profile_resource_group_name`.
- This module creates the endpoint and origin group but not origins or routes. Use [frontdoor_private_link](../frontdoor_private_link) to add origins.
