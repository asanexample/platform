# Azure Front Door Endpoint Module

## Overview

This module creates an Azure Front Door endpoint with an origin group, providing the foundation for routing and load balancing traffic to your application origins. It serves as the essential layer between the Front Door profile and the origin servers.

## Features

- Creates a Front Door endpoint and associated origin group
- Configurable custom load balancing settings for traffic distribution
- Customizable health probe configuration for monitoring origin health
- Conditional deployment capability using the `enabled` flag
- Flexible integration with existing Front Door profiles (by ID or name/resource group)
- Support for standard naming conventions and tagging

## Usage

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  # Control deployment
  enabled = true

  # Reference existing Front Door profile (use either profile_id OR profile_name + profile_resource_group_name)
  profile_id = module.frontdoor_profile.id
  # Alternative:
  # profile_name                = "fd-profile-prod-global"
  # profile_resource_group_name = "rg-cdn-prod-eastus"

  # Endpoint and origin group names
  endpoint_name     = "fd-endpoint-web"
  origin_group_name = "origin-group-web"
  
  # Optional load balancing configuration
  load_balancing_enabled = true
  load_balancing_settings = {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 2
  }
  
  # Optional health probe configuration
  health_probe_enabled = true
  health_probe_settings = {
    protocol            = "Https"
    interval_in_seconds = 30
    path                = "/healthz"
    request_type        = "GET"
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
  }
}
```

## Examples

### Basic Endpoint Configuration

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  profile_name                = "fd-profile-dev-global"
  profile_resource_group_name = "rg-cdn-dev-eastus"
  endpoint_name               = "fd-endpoint-web"
  origin_group_name           = "origin-group-web"
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Production Configuration with Advanced Load Balancing and Health Monitoring

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  profile_id        = module.frontdoor_profile.id
  endpoint_name     = "fd-endpoint-api"
  origin_group_name = "origin-group-api"
  
  load_balancing_enabled = true
  load_balancing_settings = {
    additional_latency_in_milliseconds = 50
    sample_size                        = 4
    successful_samples_required        = 3
  }
  
  health_probe_enabled = true
  health_probe_settings = {
    protocol            = "Https"
    interval_in_seconds = 60
    path                = "/health"
    request_type        = "GET"
  }
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
    Service     = "API"
  }
}
```

### Conditionally Deployed Endpoint

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  # Conditionally deploy based on environment variable
  enabled = var.deploy_staging_endpoint
  
  profile_id        = module.frontdoor_profile.id
  endpoint_name     = "fd-endpoint-staging"
  origin_group_name = "origin-group-staging"
  
  tags = {
    Environment = "Staging"
    ManagedBy   = "Terraform"
    Component   = "CDN"
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
| endpoint_name | The name of the Front Door endpoint | `string` |
| origin_group_name | The name of the origin group | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled | Controls whether the Front Door endpoint resources are deployed | `bool` | `true` | no |
| profile_id | The ID of the Front Door profile | `string` | `null` | no |
| profile_name | The name of the Front Door profile | `string` | `null` | no |
| profile_resource_group_name | The name of the resource group containing the Front Door profile | `string` | `null` | no |
| load_balancing_enabled | Whether to enable custom load balancing settings | `bool` | `false` | no |
| load_balancing_settings | Load balancing settings for the origin group | `object` | `{}` | no |
| health_probe_enabled | Whether to enable health probe | `bool` | `false` | no |
| health_probe_settings | Health probe settings for the origin group | `object` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| endpoint_id | The ID of the Front Door endpoint |
| endpoint_name | The name of the Front Door endpoint |
| endpoint_host_name | The host name of the Front Door endpoint |
| origin_group_id | The ID of the origin group |
| origin_group_name | The name of the origin group |
| enabled | Whether the Front Door endpoint is enabled |

## Module Resources

This module creates the following resources:
- Azure Front Door Endpoint
- Azure Front Door Origin Group

## Dependencies

This module depends on:
- [frontdoor_profile](../frontdoor_profile) - For the parent Front Door profile

## Load Balancing Settings

The load balancing settings control how traffic is distributed to origins within the origin group:

| Setting | Description | Default |
|---------|-------------|---------|
| additional_latency_in_milliseconds | Additional latency in milliseconds for probes to fall into the lowest latency bucket | `0` |
| sample_size | The number of samples to consider for load balancing decisions | `4` |
| successful_samples_required | The number of samples within the sample period that must succeed | `2` |

## Health Probe Settings

The health probe settings control how Front Door monitors the health of origins:

| Setting | Description | Default |
|---------|-------------|---------|
| protocol | The protocol used for the health probe (Http or Https) | `"Https"` |
| interval_in_seconds | The interval in seconds between health probes | `30` |
| path | The path to use for the health probe | `"/"` |
| request_type | The request type to use for the health probe (GET or HEAD) | `"HEAD"` |

## Notes

- Either `profile_id` OR both `profile_name` and `profile_resource_group_name` must be provided.
- This module creates the endpoint and origin group but does not create any origins or routes. Use the [frontdoor_private_link](../frontdoor_private_link) module or other appropriate modules to create origins and routes.
- The health probe path should point to a lightweight endpoint that doesn't require authentication.
- For production environments, always enable health probes to ensure traffic is routed to healthy origins.
- Front Door endpoints are globally distributed and don't have a specific Azure region.

## License

This module is licensed under the MIT License. 