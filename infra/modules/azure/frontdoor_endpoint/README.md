# Azure Front Door Endpoint Module

This module creates an Azure Front Door endpoint with an origin group. It provides the structure needed for adding origins and routes to your Front Door profile.

## Features

- Creates a Front Door endpoint and origin group
- Supports optional custom load balancing settings
- Supports optional health probe configuration
- Can be conditionally deployed using the `enabled` flag
- Provides flexibility to reference an existing Front Door profile by ID or name/resource group

## Usage

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  # Control deployment
  enabled = true

  # Reference existing Front Door profile (use either profile_id OR profile_name + profile_resource_group_name)
  profile_id = module.frontdoor_profile.id
  # Alternative:
  # profile_name                = "example-fd-profile"
  # profile_resource_group_name = "example-rg"

  # Endpoint and origin group names
  endpoint_name     = "example-endpoint"
  origin_group_name = "example-origin-group"
  
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
    environment = "dev"
    purpose     = "content-delivery"
  }
}
```

## Examples

### Basic Endpoint Configuration

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  profile_name                = "basic-fd-profile"
  profile_resource_group_name = "example-rg"
  endpoint_name               = "basic-endpoint"
  origin_group_name           = "basic-origin-group"
  
  tags = {
    environment = "dev"
  }
}
```

### Advanced Configuration with Load Balancing and Health Probe

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  profile_id        = module.frontdoor_profile.id
  endpoint_name     = "advanced-endpoint"
  origin_group_name = "advanced-origin-group"
  
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
    environment = "prod"
    criticality = "high"
  }
}
```

### Disabled Endpoint Configuration

```hcl
module "frontdoor_endpoint" {
  source = "../../modules/azure/frontdoor_endpoint"

  # Disable deployment
  enabled = false
  
  profile_id        = module.frontdoor_profile.id
  endpoint_name     = "disabled-endpoint"
  origin_group_name = "disabled-origin-group"
  
  tags = {
    environment = "dev"
  }
}
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled | Controls whether the Front Door endpoint resources are deployed | `bool` | `true` | no |
| profile_id | The ID of the Front Door profile | `string` | `null` | no |
| profile_name | The name of the Front Door profile | `string` | `null` | no |
| profile_resource_group_name | The name of the resource group containing the Front Door profile | `string` | `null` | no |
| endpoint_name | The name of the Front Door endpoint | `string` | n/a | yes |
| origin_group_name | The name of the origin group | `string` | n/a | yes |
| load_balancing_enabled | Whether to enable custom load balancing settings | `bool` | `false` | no |
| load_balancing_settings | Load balancing settings for the origin group | `object` | `{}` | no |
| health_probe_enabled | Whether to enable health probe | `bool` | `false` | no |
| health_probe_settings | Health probe settings for the origin group | `object` | `{}` | no |
| tags | A mapping of tags to assign to resources | `map(string)` | `{}` | no |

## Output Variables

| Name | Description |
|------|-------------|
| endpoint_id | The ID of the Front Door endpoint |
| endpoint_name | The name of the Front Door endpoint |
| endpoint_host_name | The host name of the Front Door endpoint |
| origin_group_id | The ID of the origin group |
| origin_group_name | The name of the origin group |
| enabled | Whether the Front Door endpoint is enabled |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | >= 3.0.0 |

## Notes

- Either `profile_id` OR both `profile_name` and `profile_resource_group_name` must be provided.
- This module creates the endpoint and origin group but does not create any origins or routes. Use the `frontdoor_private_link` module or other appropriate modules to create origins and routes. 