# Azure Resource Group Module - West US (Dev)

## Overview
This module creates and manages the Azure Resource Group for the West US region in the development environment. The resource group acts as a logical container for all related Azure resources.

## Configuration Details

### Purpose
Creates a foundational resource group that:
- Serves as a container for all Azure resources in this region and environment
- Establishes appropriate tagging and organization
- Enables resource lifecycle management and access control

### Dependencies
- **naming**: Uses standardized resource names

### Key Configuration Settings
- **Resource Group Name**: Follows naming convention from the naming module
- **Location**: West US (westus)
- **Tags**: 
  - Environment: dev
  - ManagedBy: Terragrunt
  - Project: Multi-Cloud Platform
  - DataClassification: Internal
  - CostCenter: Engineering
  - Owner: Platform Team

## Usage Example

To apply this module:
```bash
cd resource_group
terragrunt apply
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- networking
- key_vault
- storage
- aks_core
- aks_identity
- aks_node_pools 