# Azure Front Door Profile Module

Creates an Azure Front Door CDN profile -- the parent resource for endpoints, origin groups, and origins.

## Usage

```hcl
module "frontdoor_profile" {
  source = "../frontdoor_profile"

  create              = true
  name                = "fd-platform-dev-eus"
  resource_group_name = module.resource_group.name
  sku_name            = "Standard_AzureFrontDoor"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "frontdoor_profile" {
  source = "../frontdoor_profile"

  create              = false
  resource_group_name = "placeholder"
  sku_name            = "Standard_AzureFrontDoor"
}
```

### Premium SKU with custom timeout

```hcl
module "frontdoor_profile" {
  source = "../frontdoor_profile"

  create                   = true
  name                     = "fd-platform-prod-eus"
  resource_group_name      = module.resource_group.name
  sku_name                 = "Premium_AzureFrontDoor"
  response_timeout_seconds = 120

  tags = {
    Environment = "prod"
    ManagedBy   = "Terragrunt"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_cdn_frontdoor_profile.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/cdn_frontdoor_profile) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| resource_group_name | The name of the resource group in which to create the Front Door profile | `string` | n/a | yes |
| sku_name | The SKU name of the Front Door profile (Standard_AzureFrontDoor or Premium_AzureFrontDoor) | `string` | n/a | yes |
| create | Controls whether the Front Door profile is deployed | `bool` | `true` | no |
| environment | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| name | The name of the Front Door profile. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| workload | Workload name for resource names | `string` | `"platform"` | no |
| region_abbv | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| response_timeout_seconds | Response timeout in seconds. Possible values are between 16 and 240 seconds (inclusive) | `number` | `null` | no |
| tags | A mapping of tags to assign to the resource | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether the Front Door profile is created |
| id | The ID of the Front Door profile |
| name | The name of the Front Door profile |
| resource_group_name | The name of the resource group where the Front Door profile exists |
| sku_name | The SKU name of the Front Door profile |
<!-- END_TF_DOCS -->

## Dependencies

- [naming](../naming) -- standardized resource names
- [resource_group](../resource_group) -- resource group for the profile

## Notes

- Premium SKU is required for Private Link origins and advanced WAF policies.
- Front Door is a global resource; it has no region, but the resource group determines management location.
- This module creates only the profile. Use [frontdoor_endpoint](../frontdoor_endpoint) and [frontdoor_private_link](../frontdoor_private_link) for endpoints and origins.
