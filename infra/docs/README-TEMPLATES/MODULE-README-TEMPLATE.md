# [Module Name]

## Overview

Brief description of what this module does and its purpose in the infrastructure.

## Features

- Key feature 1
- Key feature 2
- Key feature 3
- ...

## Usage

```hcl
module "example" {
  source = "../../modules/azure/[module_name]"

  # Required parameters
  resource_group_name = "example-rg"
  location            = "eastus"
  
  # Optional parameters
  example_parameter   = "value"
  
  # Tags
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Basic Usage

```hcl
module "example" {
  source = "../../modules/azure/[module_name]"

  # Minimum required configuration
  resource_group_name = "example-rg"
  location            = "eastus"
}
```

### Advanced Usage

```hcl
module "example" {
  source = "../../modules/azure/[module_name]"

  # Advanced configuration example
  resource_group_name = "example-rg"
  location            = "eastus"
  advanced_feature    = true
  
  # Additional configuration
  example_map = {
    key1 = "value1"
    key2 = "value2"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | 4.25.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | 4.25.0 |

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| resource_group_name | The name of the resource group | `string` |
| location | The Azure region where resources will be created | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| name | Custom name for the resource | `string` | `""` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the created resource |
| name | The name of the created resource |

## Validation Rules

The module includes the following validation rules:

- Validation rule 1
- Validation rule 2
- ...

## Dependencies

This module can depend on:
- [naming](../naming) - For standardized resource naming
- [resource_group](../resource_group) - For resource group creation

## Module Resources

This module creates the following resources:
- Resource 1
- Resource 2
- ...

## Notes

- Important note 1
- Important note 2
- ...

## License

This module is licensed under the MIT License. 