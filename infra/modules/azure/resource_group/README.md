# Azure Resource Group Module

## Overview

This module creates an Azure resource group with standardized naming. Resource groups are logical containers for Azure resources and provide a way to manage permissions, billing, and resource lifecycle.

## Features

- Creates a standard Azure Resource Group
- Validates resource group name according to Azure naming rules
- Validates location against the list of supported Azure regions
- Supports optional tagging for better resource organization

## Usage

```hcl
module "resource_group" {
  source = "../../modules/azure/resource_group"

  name     = "app-rg-eastus-prod"
  location = "eastus"
  tags = {
    Environment = "Production"
    ManagedBy   = "Terraform"
    Owner       = "Platform Team"
  }
}
```

## Examples

### Basic Usage

```hcl
module "resource_group" {
  source = "../../modules/azure/resource_group"

  name     = "app-rg-eastus-prod"
  location = "eastus"
}
```

### With Tags and Naming Convention

```hcl
module "resource_group" {
  source = "../../modules/azure/resource_group"

  name     = "vip-rg-dev-eus-networking"
  location = "eastus"
  tags = {
    Environment        = "Development"
    ManagedBy          = "Terraform"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | 4.23.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | 4.23.0 |

## Required Inputs

| Name | Description | Type | 
|------|-------------|------|
| name | Name of the resource group | `string` |
| location | Azure region where the resource group will be created | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| tags | Tags to apply to the resource group | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| name | The name of the resource group |
| id | The ID of the resource group |
| location | The location of the resource group |

## Validation Rules

The module includes the following validation rules:

- Resource group name must be between 1 and 90 characters
- Resource group name can only include alphanumeric, hyphen, underscore, parentheses, and period characters
- Location must be a valid Azure region name

## Dependencies

This module doesn't have external dependencies, but it is commonly used by other modules.

## Module Resources

This module creates the following resources:
- Azure Resource Group

## Notes

- Resource groups are fundamental building blocks for Azure resource organization
- Best practice is to use consistent naming conventions for resource groups
- Consider using region-specific resource groups for better management of regional resources
- Resource group deletion will also delete all resources contained within it

## License

This module is licensed under the MIT License. 