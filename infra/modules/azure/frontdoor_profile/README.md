# Azure Front Door Profile Module

This module creates an Azure Front Door profile, which is the parent resource for Front Door endpoints, origin groups, and other Front Door components.

## Features

- Creates an Azure Front Door profile with configurable settings
- Supports both Standard and Premium SKUs
- Allows configuration of response timeout
- Includes validation for all input parameters

## Usage

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                = "example-fd-profile"
  resource_group_name = "example-rg"
  sku_name            = "Standard_AzureFrontDoor"
  
  # Optional
  response_timeout_seconds = 60
  
  tags = {
    environment = "dev"
    purpose     = "content-delivery"
  }
}
```

## Examples

### Basic Front Door Profile

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                = "basic-fd-profile"
  resource_group_name = "example-rg"
  sku_name            = "Standard_AzureFrontDoor"
  
  tags = {
    environment = "dev"
  }
}
```

### Premium Front Door Profile with Custom Response Timeout

```hcl
module "frontdoor_profile" {
  source = "../../modules/azure/frontdoor_profile"

  name                     = "premium-fd-profile"
  resource_group_name      = "example-rg"
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = 120
  
  tags = {
    environment = "prod"
    criticality = "high"
  }
}
```

## Input Variables

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | The name of the Front Door profile | `string` | n/a | yes |
| resource_group_name | The name of the resource group in which to create the Front Door profile | `string` | n/a | yes |
| sku_name | The SKU name of the Front Door profile (Standard_AzureFrontDoor or Premium_AzureFrontDoor) | `string` | n/a | yes |
| response_timeout_seconds | Response timeout in seconds (16-240) | `number` | `null` | no |
| tags | A mapping of tags to assign to the resource | `map(string)` | `{}` | no |

## Output Variables

| Name | Description |
|------|-------------|
| id | The ID of the Front Door profile |
| name | The name of the Front Door profile |
| resource_group_name | The name of the resource group where the Front Door profile exists |
| sku_name | The SKU name of the Front Door profile |

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | >= 3.0.0 |

## Notes

- The Standard SKU supports basic Front Door functionality, while the Premium SKU supports additional features such as Private Link and Web Application Firewall (WAF) policies.
- Response timeout seconds must be between 16 and 240 seconds inclusive. 