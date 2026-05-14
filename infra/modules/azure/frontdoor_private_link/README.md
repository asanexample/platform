# Azure Front Door Private Link Module

Creates a Front Door origin with Private Link connectivity to an Azure Storage account, and optionally creates a route.

## Usage

```hcl
module "frontdoor_private_link" {
  source = "../frontdoor_private_link"

  create          = true
  origin_group_id = module.frontdoor_endpoint.origin_group_id
  origin_name     = "origin-static"

  storage_account_name        = module.storage.name
  storage_resource_group_name = module.resource_group.name
  storage_account_id          = module.storage.id
  storage_primary_blob_host   = module.storage.primary_blob_host
  storage_primary_web_host    = module.storage.primary_web_host
  storage_location            = "eastus"
  use_blob_endpoint           = true

  route_enabled = true
  endpoint_id   = module.frontdoor_endpoint.endpoint_id
  route_name    = "route-static"

  cache_enabled = true
  cache_settings = {
    query_string_caching_behavior = "UseQueryString"
    compression_enabled           = true
    content_types_to_compress     = ["text/html", "text/css", "application/javascript"]
  }
}
```

## Examples

### Disabled

```hcl
module "frontdoor_private_link" {
  source = "../frontdoor_private_link"

  create                      = false
  origin_name                 = "placeholder"
  storage_account_name        = "placeholder"
  storage_resource_group_name = "placeholder"
  storage_account_id          = "placeholder"
  storage_primary_blob_host   = "placeholder"
  storage_primary_web_host    = "placeholder"
  storage_location            = "eastus"
}
```

### Origin without a route (multi-origin setup)

```hcl
module "frontdoor_private_link" {
  source = "../frontdoor_private_link"

  create          = true
  origin_group_id = module.frontdoor_endpoint.origin_group_id
  origin_name     = "origin-secondary"

  storage_account_name        = "staprodsecondary"
  storage_resource_group_name = "rg-storage-prod-wus"
  storage_account_id          = module.storage_secondary.id
  storage_primary_blob_host   = module.storage_secondary.primary_blob_host
  storage_primary_web_host    = module.storage_secondary.primary_web_host
  storage_location            = "westus"

  priority      = 2
  weight        = 500
  route_enabled = false
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_cdn_frontdoor_origin.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_origin) | resource |
| [azurerm_cdn_frontdoor_route.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_route) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| origin_name | The name of the origin | `string` | n/a | yes |
| storage_account_id | The resource ID of the storage account | `string` | n/a | yes |
| storage_account_name | The name of the storage account | `string` | n/a | yes |
| storage_location | The Azure region where the storage account is located | `string` | n/a | yes |
| storage_primary_blob_host | The primary blob host of the storage account (e.g., storageaccount.blob.core.windows.net) | `string` | n/a | yes |
| storage_primary_web_host | The primary web host of the storage account (e.g., storageaccount.web.core.windows.net) | `string` | n/a | yes |
| storage_resource_group_name | The name of the resource group containing the storage account | `string` | n/a | yes |
| cache_enabled | Whether to enable caching for this route | `bool` | `true` | no |
| cache_settings | Cache settings for the route | <pre>object({<br/>    query_string_caching_behavior = optional(string, "UseQueryString")<br/>    query_strings                 = optional(list(string))<br/>    compression_enabled           = optional(bool, false)<br/>    content_types_to_compress     = optional(list(string))<br/>  })</pre> | <pre>{<br/>  "compression_enabled": false,<br/>  "query_string_caching_behavior": "UseQueryString"<br/>}</pre> | no |
| certificate_name_check_enabled | Whether to enable certificate name check | `bool` | `true` | no |
| create | Controls whether the Front Door Private Link module is deployed | `bool` | `true` | no |
| enabled | Whether the origin is enabled | `bool` | `true` | no |
| endpoint_id | The ID of the Front Door endpoint. Required if route_enabled is true. | `string` | `null` | no |
| forwarding_protocol | Protocol to use when forwarding traffic | `string` | `"HttpsOnly"` | no |
| https_redirect_enabled | Whether to enable HTTPS redirect | `bool` | `true` | no |
| link_to_default_domain | Whether to link to the default domain | `bool` | `true` | no |
| origin_group_id | The ID of the Front Door origin group. If provided, origin_group_name, profile_name, and profile_resource_group_name are not required. | `string` | `null` | no |
| origin_group_name | The name of the Front Door origin group. Required if origin_group_id is not provided. | `string` | `null` | no |
| patterns_to_match | The route patterns to match | `list(string)` | <pre>[<br/>  "/*"<br/>]</pre> | no |
| priority | Priority of origin in given origin group | `number` | `1` | no |
| private_link_request_message | The message to include in the request for private link approval | `string` | `"Request access for Private Link Origin CDN Frontdoor"` | no |
| profile_name | The name of the Front Door profile. Required if origin_group_id is not provided. | `string` | `null` | no |
| profile_resource_group_name | The name of the resource group containing the Front Door profile. Required if origin_group_id is not provided. | `string` | `null` | no |
| route_enabled | Whether to create a route for this origin | `bool` | `true` | no |
| route_name | The name of the route. Required if route_enabled is true. | `string` | `null` | no |
| supported_protocols | Supported protocols for this route | `list(string)` | <pre>[<br/>  "Http",<br/>  "Https"<br/>]</pre> | no |
| use_blob_endpoint | Whether to use the blob endpoint instead of the web endpoint | `bool` | `true` | no |
| weight | Weight of origin in given origin group | `number` | `500` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether the Front Door Private Link module is created |
| origin_host_name | The host name of the origin |
| origin_id | The ID of the Front Door origin |
| origin_name | The name of the origin |
| private_link_request_message | The approval message used for the private link |
| private_link_target_id | The target ID of the private link |
| route_id | The ID of the route, if created |
| route_name | The name of the route, if created |
<!-- END_TF_DOCS -->

## Dependencies

- [frontdoor_endpoint](../frontdoor_endpoint) -- provides the origin group and endpoint
- [storage_account](../storage_account) -- the storage account connected via Private Link

## Notes

- Requires the Premium Front Door SKU for Private Link functionality.
- After deployment, the Private Link connection may require manual approval in the Azure Portal if the deploying identity lacks auto-approve permissions.
- Provide either `origin_group_id` or all of `origin_group_name`, `profile_name`, and `profile_resource_group_name`.
