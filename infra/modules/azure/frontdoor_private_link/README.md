# Azure Front Door Private Link Origin Module

## Overview

This module creates an Azure Front Door origin with Private Link configuration, enabling secure private connectivity to backend services like storage accounts. It optionally configures a route to expose the private service through Front Door with customizable caching and routing rules.

## Features

- Creates a Front Door origin with Private Link integration for secure connectivity
- Supports both blob and web endpoints of Azure Storage accounts
- Configurable origin priority and weight for traffic distribution
- Optional route creation with customizable patterns and protocols
- Flexible caching configuration for performance optimization
- Comprehensive validation for all input parameters
- Secure communication through HTTPS enforcement options

## Usage

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  # Origin group reference (use either origin_group_id OR origin_group_name + profile_name + profile_resource_group_name)
  origin_group_id = module.frontdoor_endpoint.origin_group_id
  # Alternative:
  # origin_group_name           = "origin-group-web"
  # profile_name                = "fd-profile-prod-global"
  # profile_resource_group_name = "rg-cdn-prod-eastus"

  # Storage account to connect to
  storage_account_name        = "staprodstatic001"
  storage_resource_group_name = "rg-storage-prod-eastus"
  use_blob_endpoint           = true # Set to false to use web endpoint instead
  
  # Origin configuration
  origin_name                   = "origin-storage-static"
  private_link_request_message  = "Request access for Front Door Private Link Origin"
  
  # Route configuration (optional)
  route_enabled        = true
  endpoint_id          = module.frontdoor_endpoint.endpoint_id
  route_name           = "route-static-content"
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

  origin_group_id             = module.frontdoor_endpoint.origin_group_id
  storage_account_name        = "stadevstatic001"
  storage_resource_group_name = "rg-storage-dev-eastus"
  origin_name                 = "origin-blob-static"
  
  # Connect to endpoint
  endpoint_id  = module.frontdoor_endpoint.endpoint_id
  route_name   = "route-static-content"
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Advanced Configuration with Web Endpoint and Custom Caching

```hcl
module "frontdoor_private_link" {
  source = "../../modules/azure/frontdoor_private_link"

  origin_group_name           = "origin-group-web"
  profile_name                = "fd-profile-prod-global"
  profile_resource_group_name = "rg-cdn-prod-eastus"
  
  storage_account_name        = "staprodweb001"
  storage_resource_group_name = "rg-storage-prod-eastus"
  use_blob_endpoint           = false # Use web endpoint instead
  
  origin_name                 = "origin-web-content"
  priority                    = 2
  weight                      = 800
  
  route_enabled               = true
  endpoint_id                 = module.frontdoor_endpoint.endpoint_id
  route_name                  = "route-web-content"
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
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
    ContentType = "Web"
  }
}
```

### Multi-Origin Configuration with Weighted Load Balancing

```hcl
# Primary origin
module "frontdoor_private_link_primary" {
  source = "../../modules/azure/frontdoor_private_link"

  origin_group_id             = module.frontdoor_endpoint.origin_group_id
  storage_account_name        = "staprodprimary001"
  storage_resource_group_name = "rg-storage-prod-eastus"
  origin_name                 = "origin-primary"
  
  # Higher priority, higher weight for primary
  priority                    = 1
  weight                      = 1000
  
  # Route configuration
  route_enabled               = false # No route, as we'll create a single route for both origins
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Role        = "Primary"
  }
}

# Secondary origin
module "frontdoor_private_link_secondary" {
  source = "../../modules/azure/frontdoor_private_link"

  origin_group_id             = module.frontdoor_endpoint.origin_group_id
  storage_account_name        = "staprodsecondary001"
  storage_resource_group_name = "rg-storage-prod-westus"
  origin_name                 = "origin-secondary"
  
  # Lower priority, lower weight for secondary
  priority                    = 2
  weight                      = 500
  
  # Route configuration
  route_enabled               = true
  endpoint_id                 = module.frontdoor_endpoint.endpoint_id
  route_name                  = "route-content"
  patterns_to_match           = ["/*"]
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Role        = "Secondary"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| storage_account_name | The name of the storage account to connect to | `string` |
| storage_resource_group_name | The name of the resource group containing the storage account | `string` |
| origin_name | The name of the Front Door origin | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| origin_group_id | The ID of the Front Door origin group | `string` | `null` | no |
| origin_group_name | The name of the Front Door origin group | `string` | `null` | no |
| profile_name | The name of the Front Door profile | `string` | `null` | no |
| profile_resource_group_name | The name of the resource group containing the Front Door profile | `string` | `null` | no |
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
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

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

## Module Resources

This module creates the following resources:
- Azure Front Door Origin with Private Link configuration
- Azure Front Door Route (optional)

## Dependencies

This module depends on:
- [frontdoor_profile](../frontdoor_profile) - For the parent Front Door profile
- [frontdoor_endpoint](../frontdoor_endpoint) - For the Front Door endpoint and origin group

## Private Link Configuration

Private Link provides the following benefits:
- Secure access to Azure Storage accounts (blob or web endpoints)
- Traffic remains on the Microsoft backbone network, not traversing the internet
- Service endpoint provides IP firewall protection
- Content can only be accessed through Azure Front Door, not directly

## Caching Configuration Options

The cache settings allow you to configure how Front Door caches content:

| Setting | Description | Options |
|---------|-------------|---------|
| query_string_caching_behavior | How query strings affect caching | `UseQueryString`, `IgnoreQueryString`, `NotSet` |
| compression_enabled | Whether to enable compression | `true`, `false` |
| content_types_to_compress | MIME types to compress | List of strings |

## Notes

- Either `origin_group_id` OR all of `origin_group_name`, `profile_name`, and `profile_resource_group_name` must be provided.
- If `route_enabled` is true, both `endpoint_id` and `route_name` must be provided.
- After deploying, you may need to manually approve the private link connection in the Azure Portal if using an identity that doesn't have the appropriate permissions to auto-approve.
- For production environments, the Premium SKU of Front Door is required for Private Link functionality.
- Storage accounts must allow Microsoft.Network as a trusted service.
- Using a unique `private_link_request_message` helps identify approval requests in multi-account environments.

## License

This module is licensed under the MIT License. 