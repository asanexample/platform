# Front Door Private Link

Creates an Azure Front Door origin with Private Link connectivity to a storage account and optionally creates a route for the origin. This enables Front Door to securely access private storage backends (blob or static website endpoints) without exposing them to the public internet. The Private Link connection requires manual approval on the storage account side.

## Usage

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  origin_group_id             = "/subscriptions/.../originGroups/fdog-platform-dev-eus"
  origin_name                 = "fdo-platform-dev-eus"
  storage_account_name        = "stplatdeveus001"
  storage_resource_group_name = "rg-platform-dev-eus"
  storage_account_id          = "/subscriptions/.../storageAccounts/stplatdeveus001"
  storage_location            = "eastus"
  storage_primary_blob_host   = "stplatdeveus001.blob.core.windows.net"
  storage_primary_web_host    = "stplatdeveus001.z13.web.core.windows.net"

  use_blob_endpoint = true

  route_enabled = true
  endpoint_id   = "/subscriptions/.../endpoints/fde-platform-dev-eus"
  route_name    = "fdr-platform-dev-eus"
}
```

## Examples

### Disabled Module

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"
  create = false
}
```

### Static Website Endpoint with Caching

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  origin_group_id             = "/subscriptions/.../originGroups/fdog-web-dev-eus"
  origin_name                 = "fdo-web-dev-eus"
  storage_account_name        = "stwebdeveus001"
  storage_resource_group_name = "rg-platform-dev-eus"
  storage_account_id          = "/subscriptions/.../storageAccounts/stwebdeveus001"
  storage_location            = "eastus"
  storage_primary_blob_host   = "stwebdeveus001.blob.core.windows.net"
  storage_primary_web_host    = "stwebdeveus001.z13.web.core.windows.net"

  use_blob_endpoint = false

  route_enabled = true
  endpoint_id   = "/subscriptions/.../endpoints/fde-web-dev-eus"
  route_name    = "fdr-web-dev-eus"

  cache_enabled = true
  cache_settings = {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = ["text/html", "text/css", "application/javascript"]
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
| [azurerm_cdn_frontdoor_origin.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_origin) | resource |
| [azurerm_cdn_frontdoor_route.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_route) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_origin_name"></a> [origin\_name](#input\_origin\_name) | The name of the origin | `string` | n/a | yes |
| <a name="input_storage_account_id"></a> [storage\_account\_id](#input\_storage\_account\_id) | The resource ID of the storage account | `string` | n/a | yes |
| <a name="input_storage_account_name"></a> [storage\_account\_name](#input\_storage\_account\_name) | The name of the storage account | `string` | n/a | yes |
| <a name="input_storage_location"></a> [storage\_location](#input\_storage\_location) | The Azure region where the storage account is located | `string` | n/a | yes |
| <a name="input_storage_primary_blob_host"></a> [storage\_primary\_blob\_host](#input\_storage\_primary\_blob\_host) | The primary blob host of the storage account (e.g., storageaccount.blob.core.windows.net) | `string` | n/a | yes |
| <a name="input_storage_primary_web_host"></a> [storage\_primary\_web\_host](#input\_storage\_primary\_web\_host) | The primary web host of the storage account (e.g., storageaccount.web.core.windows.net) | `string` | n/a | yes |
| <a name="input_storage_resource_group_name"></a> [storage\_resource\_group\_name](#input\_storage\_resource\_group\_name) | The name of the resource group containing the storage account | `string` | n/a | yes |
| <a name="input_cache_enabled"></a> [cache\_enabled](#input\_cache\_enabled) | Whether to enable caching for this route | `bool` | `true` | no |
| <a name="input_cache_settings"></a> [cache\_settings](#input\_cache\_settings) | Cache settings for the route | <pre>object({<br/>    query_string_caching_behavior = optional(string, "UseQueryString")<br/>    query_strings                 = optional(list(string))<br/>    compression_enabled           = optional(bool, false)<br/>    content_types_to_compress     = optional(list(string))<br/>  })</pre> | <pre>{<br/>  "compression_enabled": false,<br/>  "query_string_caching_behavior": "UseQueryString"<br/>}</pre> | no |
| <a name="input_certificate_name_check_enabled"></a> [certificate\_name\_check\_enabled](#input\_certificate\_name\_check\_enabled) | Whether to enable certificate name check | `bool` | `true` | no |
| <a name="input_create"></a> [create](#input\_create) | Controls whether the Front Door Private Link module is deployed | `bool` | `true` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Whether the origin is enabled | `bool` | `true` | no |
| <a name="input_endpoint_id"></a> [endpoint\_id](#input\_endpoint\_id) | The ID of the Front Door endpoint. Required if route\_enabled is true. | `string` | `null` | no |
| <a name="input_forwarding_protocol"></a> [forwarding\_protocol](#input\_forwarding\_protocol) | Protocol to use when forwarding traffic | `string` | `"HttpsOnly"` | no |
| <a name="input_https_redirect_enabled"></a> [https\_redirect\_enabled](#input\_https\_redirect\_enabled) | Whether to enable HTTPS redirect | `bool` | `true` | no |
| <a name="input_link_to_default_domain"></a> [link\_to\_default\_domain](#input\_link\_to\_default\_domain) | Whether to link to the default domain | `bool` | `true` | no |
| <a name="input_origin_group_id"></a> [origin\_group\_id](#input\_origin\_group\_id) | The ID of the Front Door origin group. If provided, origin\_group\_name, profile\_name, and profile\_resource\_group\_name are not required. | `string` | `null` | no |
| <a name="input_origin_group_name"></a> [origin\_group\_name](#input\_origin\_group\_name) | The name of the Front Door origin group. Required if origin\_group\_id is not provided. | `string` | `null` | no |
| <a name="input_patterns_to_match"></a> [patterns\_to\_match](#input\_patterns\_to\_match) | The route patterns to match | `list(string)` | <pre>[<br/>  "/*"<br/>]</pre> | no |
| <a name="input_priority"></a> [priority](#input\_priority) | Priority of origin in given origin group | `number` | `1` | no |
| <a name="input_private_link_request_message"></a> [private\_link\_request\_message](#input\_private\_link\_request\_message) | The message to include in the request for private link approval | `string` | `"Request access for Private Link Origin CDN Frontdoor"` | no |
| <a name="input_profile_name"></a> [profile\_name](#input\_profile\_name) | The name of the Front Door profile. Required if origin\_group\_id is not provided. | `string` | `null` | no |
| <a name="input_profile_resource_group_name"></a> [profile\_resource\_group\_name](#input\_profile\_resource\_group\_name) | The name of the resource group containing the Front Door profile. Required if origin\_group\_id is not provided. | `string` | `null` | no |
| <a name="input_route_enabled"></a> [route\_enabled](#input\_route\_enabled) | Whether to create a route for this origin | `bool` | `true` | no |
| <a name="input_route_name"></a> [route\_name](#input\_route\_name) | The name of the route. Required if route\_enabled is true. | `string` | `null` | no |
| <a name="input_supported_protocols"></a> [supported\_protocols](#input\_supported\_protocols) | Supported protocols for this route | `list(string)` | <pre>[<br/>  "Http",<br/>  "Https"<br/>]</pre> | no |
| <a name="input_use_blob_endpoint"></a> [use\_blob\_endpoint](#input\_use\_blob\_endpoint) | Whether to use the blob endpoint instead of the web endpoint | `bool` | `true` | no |
| <a name="input_weight"></a> [weight](#input\_weight) | Weight of origin in given origin group | `number` | `500` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether the Front Door Private Link module is created |
| <a name="output_origin_host_name"></a> [origin\_host\_name](#output\_origin\_host\_name) | The host name of the origin |
| <a name="output_origin_id"></a> [origin\_id](#output\_origin\_id) | The ID of the Front Door origin |
| <a name="output_origin_name"></a> [origin\_name](#output\_origin\_name) | The name of the origin |
| <a name="output_private_link_request_message"></a> [private\_link\_request\_message](#output\_private\_link\_request\_message) | The approval message used for the private link |
| <a name="output_private_link_target_id"></a> [private\_link\_target\_id](#output\_private\_link\_target\_id) | The target ID of the private link |
| <a name="output_route_id"></a> [route\_id](#output\_route\_id) | The ID of the route, if created |
| <a name="output_route_name"></a> [route\_name](#output\_route\_name) | The name of the route, if created |
<!-- END_TF_DOCS -->

## Notes

- The Private Link connection requires approval on the storage account. The `private_link_request_message` is sent as the approval request message.
- Set `use_blob_endpoint = true` for blob storage origins or `false` for static website (`$web`) origins. This controls both the `host_name` and the Private Link `target_type`.
- When `route_enabled = true`, an `endpoint_id` and `route_name` must be provided. HTTPS redirect is enabled by default.
- Caching is enabled by default with `UseQueryString` behavior. Disable with `cache_enabled = false`.
