# Azure Front Door Profile Module

## Overview

This module creates an Azure Front Door profile, which serves as the parent resource for Front Door endpoints, origin groups, and other Front Door components. It provides the foundation for building a global content delivery network in Azure.

## Features

- Creates an Azure Front Door profile with configurable settings
- Supports both Standard and Premium SKUs
- Configurable response timeout for optimizing performance
- Conditional deployment using the `enabled` flag
- Comprehensive input validation for all parameters
- Consistent tagging and naming conventions

## Usage

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                = "fd-profile-prod-global"
  resource_group_name = "rg-cdn-prod-eastus"
  sku_name            = "Standard_AzureFrontDoor"
  
  # Optional
  enabled                  = true
  response_timeout_seconds = 60
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
  }
}
```

## Examples

### Basic Front Door Profile (Standard SKU)

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                = "fd-profile-dev-global"
  resource_group_name = "rg-cdn-dev-eastus"
  sku_name            = "Standard_AzureFrontDoor"
  
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

### Premium Front Door Profile with Custom Timeout

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                     = "fd-profile-prod-global"
  resource_group_name      = "rg-cdn-prod-eastus"
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = 120
  
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Component   = "CDN"
    Criticality = "High"
  }
}
```

### Conditionally Disabled Front Door Profile

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  enabled                  = var.deploy_frontdoor
  name                     = "fd-profile-staging-global"
  resource_group_name      = "rg-cdn-staging-eastus"
  sku_name                 = "Standard_AzureFrontDoor"
  
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
| name | The name of the Front Door profile | `string` |
| resource_group_name | The name of the resource group in which to create the Front Door profile | `string` |
| sku_name | The SKU name of the Front Door profile (Standard_AzureFrontDoor or Premium_AzureFrontDoor) | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| enabled | Controls whether the Front Door profile is deployed | `bool` | `true` | no |
| response_timeout_seconds | Response timeout in seconds (16-240) | `number` | `null` | no |
| tags | A mapping of tags to assign to the resource | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the Front Door profile |
| name | The name of the Front Door profile |
| resource_group_name | The name of the resource group where the Front Door profile exists |
| sku_name | The SKU name of the Front Door profile |
| enabled | Whether the Front Door profile is enabled |

## Module Resources

This module creates the following resources:
- Azure Front Door Profile

## Dependencies

This module can depend on:
- [resource_group](../resource_group) - For resource group creation

## SKU Features Comparison

### Standard SKU
- Global content delivery network
- Dynamic site acceleration
- DDoS protection
- Basic WAF capabilities
- Rules engine
- HTTP/2 support

### Premium SKU
- All Standard SKU features
- Advanced WAF capabilities
- Private Link integration
- Integration with Azure managed certificates
- Enhanced security features
- Improved routing capabilities

## Notes

- The Standard SKU supports basic Front Door functionality, while the Premium SKU supports additional features such as Private Link and Web Application Firewall (WAF) policies.
- Response timeout seconds must be between 16 and 240 seconds inclusive.
- Front Door Profile is a global resource and doesn't have a specific Azure region.
- This module creates only the profile; use companion modules for endpoints, origin groups, and origins.
- Consider using the Premium SKU for applications with strict security requirements or needing Private Link integration.

## License

This module is licensed under the MIT License. 