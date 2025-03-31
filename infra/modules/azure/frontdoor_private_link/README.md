# Azure Front Door Private Link Origin Module

This module creates an Azure Front Door origin with private link configuration to securely connect to private resources like storage accounts, with optional route configuration.

## Features

- Creates a Front Door origin with private link to a storage account
- Supports both blob and web endpoints of storage accounts
- Optionally creates a route for the origin
- Includes comprehensive validation for all input parameters
- Configurable caching settings for routes

## Usage

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  # Origin group reference (use either origin_group_id OR origin_group_name + profile_name + profile_resource_group_name)
  origin_group_id = module.frontdoor_endpoint.origin_group_id
  # Alternative:
  # origin_group_name           = "example-origin-group"
  # profile_name                = "example-fd-profile"
  # profile_resource_group_name = "example-rg"

  # Storage account to connect to
  storage_account_name        = "examplestorageaccount"
  storage_resource_group_name = "example-rg"
  use_blob_endpoint           = true # Set to false to use web endpoint instead
  
  # Origin configuration
  origin_name                   = "example-storage-origin"
  private_link_request_message  = "Request access for Private Link Origin CDN Frontdoor"
  
  # Route configuration (optional)
  route_enabled        = true
  endpoint_id          = module.frontdoor_endpoint.endpoint_id
  route_name           = "example-storage-route"
  patterns_to_match    = ["/*"]
  forwarding_protocol  = "HttpsOnly"
  supported_protocols  = ["Http", "Https"]
  
  # Caching configuration (optional)
  cache_enabled = true
  cache_settings = {
    query_string_caching_behavior = "UseQueryString"
    compression_enabled           = true
    content_types_to_compress     = [
      "application/json",
      "text/html",
      "text/css"
    ]
  }
}
```

## Examples

### Basic Storage Account with Blob Endpoint

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  origin_group_id            = module.frontdoor_endpoint.origin_group_id
  storage_account_name       = "basicstorageaccount"
  storage_resource_group_name = "example-rg"
  origin_name                = "basic-storage-origin"
  
  # Connect to endpoint
  endpoint_id  = module.frontdoor_endpoint.endpoint_id
  route_name   = "basic-storage-route"
}
```

### Advanced Configuration with Web Endpoint and Custom Caching

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  origin_group_name           = "advanced-origin-group"
  profile_name                = "advanced-fd-profile"
  profile_resource_group_name = "example-rg"
  
  storage_account_name        = "advancedstorage"
  storage_resource_group_name = "example-rg"
  use_blob_endpoint           = false # Use web endpoint instead
  
  origin_name                 = "advanced-storage-origin"
  priority                    = 2
  weight                      = 800
  
  route_enabled               = true
  endpoint_id                 = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/example-rg/providers/Microsoft.Cdn/profiles/advanced-fd-profile/endpoints/advanced-endpoint"
  route_name                  = "advanced-storage-route"
  patterns_to_match           = ["/images/*", "/documents/*"]
  
  cache_enabled               = true
  cache_settings = {
    query_string_caching_behavior = "IgnoreQueryString"
    compression_enabled           = true
    content_types_to_compress     = [
      "application/json",
      "text/html",
      "text/css",
      "text/javascript",
      "application/javascript"
    ]
  }
}
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| origin_group_id | The ID of the Front Door origin group | `string` | `null` | no |
| origin_group_name | The name of the Front Door origin group | `string` | `null` | no |
| profile_name | The name of the Front Door profile | `string` | `null` | no |
| profile_resource_group_name | The name of the resource group containing the Front Door profile | `string` | `null` | no |
| storage_account_name | The name of the storage account | `string` | n/a | yes |
| storage_resource_group_name | The name of the resource group containing the storage account | `string` | n/a | yes |
| origin_name | The name of the origin | `string` | n/a | yes |
| enabled | Whether the origin is enabled | `bool` | `true` | no |
| certificate_name_check_enabled | Whether to enable certificate name check | `bool` | `true` | no |
| use_blob_endpoint | Whether to use the blob endpoint instead of the web endpoint | `bool` | `true` | no |
| priority | Priority of origin in given origin group (1-5) | `number` | `1` | no |
| weight | Weight of origin in given origin group (1-1000) | `number` | `500` | no |
| private_link_request_message | Message for private link approval | `string` | `"Request access for Private Link Origin CDN Frontdoor"` | no |
| route_enabled | Whether to create a route for this origin | `bool` | `true` | no |
| endpoint_id | The ID of the Front Door endpoint | `string` | `null` | no |
| route_name | The name of the route | `string` | `null` | no |
| forwarding_protocol | Protocol for forwarding traffic | `string` | `"HttpsOnly"` | no |
| https_redirect_enabled | Whether to enable HTTPS redirect | `bool` | `true` | no |
| patterns_to_match | Route patterns to match | `list(string)` | `["/*"]` | no |
| supported_protocols | Supported protocols for the route | `list(string)` | `["Http", "Https"]` | no |
| link_to_default_domain | Whether to link to default domain | `bool` | `true` | no |
| cache_enabled | Whether to enable caching | `bool` | `true` | no |
| cache_settings | Cache settings for the route | `object` | See variables.tf | no |

## Output Variables

| Name | Description |
|------|-------------|
| origin_id | The ID of the Front Door origin |
| origin_name | The name of the origin |
| origin_host_name | The host name of the origin |
| private_link_id | The ID of the private link |
| private_link_status | The status of the private link |
| private_link_approval_message | The approval message used for the private link |
| route_id | The ID of the route, if created |
| route_name | The name of the route, if created |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | >= 3.0.0 |

## Notes

- Either `origin_group_id` OR all of `origin_group_name`, `profile_name`, and `profile_resource_group_name` must be provided.
- If `route_enabled` is true, both `endpoint_id` and `route_name` must be provided.
- After deploying, you may need to manually approve the private link connection in the Azure Portal if using an identity that doesn't have the appropriate permissions to auto-approve. 