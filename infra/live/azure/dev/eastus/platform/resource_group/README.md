# Azure Resource Group - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for deploying and managing the Azure Resource Group in the East US region for the development environment. The resource group acts as a logical container for all related Azure resources.

## Configuration Details

### Purpose

This configuration:
- Creates a foundational resource group that serves as a container for all Azure resources in this region and environment
- Establishes appropriate tagging and organization
- Enables resource lifecycle management and access control
- Follows the company's naming convention standards

### Dependencies

This configuration depends on:
- **naming**: Uses standardized resource naming conventions for consistent and compliant resource names

### Key Configuration Settings

- **Resource Group**:
  - Name: Follows naming convention from the naming module
  - Location: East US (eastus)
  - Tags: 
    - Environment: dev
    - ManagedBy: Terragrunt
    - Project: Multi-Cloud Platform
    - DataClassification: Internal
    - CostCenter: Engineering
    - Owner: Platform Team

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/resource_group
terragrunt plan
terragrunt apply
```

## Dependencies on this Configuration

The following modules depend on outputs from this configuration:
- networking
- key_vault
- storage
- aks_core
- aks_identity
- aks_node_pools

## Implementation Notes

Resource groups are foundational resources that must be deployed before any other Azure resources. Deleting this resource group will also delete all the resources contained within it, so caution should be exercised when managing this resource in production environments. 