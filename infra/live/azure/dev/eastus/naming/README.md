# Azure Naming Module - West US (Dev)

## Overview
This module creates standardized names for Azure resources following organizational naming conventions. It ensures all resources across the infrastructure use consistent naming patterns.

## Configuration Details

### Purpose
Centralizes naming standards and generates resource names that:
- Follow company-wide naming conventions
- Adhere to Azure limitations and requirements
- Include consistent prefixes, environment identifiers, and other components

### Dependencies
- None (Root module with no dependencies)

### Inputs
- Automatically uses environment variables from `../common.hcl`
- Uses configurable prefix from `common.hcl` (defaults to `vip` if not specified)
- Environment: `dev`
- Region: `westus`

### Outputs
Standardized resource names for:
- Resource groups
- Virtual networks
- Storage accounts
- Key vaults
- AKS clusters
- And other Azure resources

## Usage Example

To apply this module:
```bash
cd naming
terragrunt apply
```

To customize the prefix for your organization, modify the `prefix` variable in `common.hcl`.

## Dependencies on this Module
The following modules depend on outputs from this module:
- networking
- resource_group
- storage
- key_vault
- aks_core
- aks_node_pools 