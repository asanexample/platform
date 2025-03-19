# Hosting Composite Module

This module is a composite module that integrates multiple infrastructure components to provide a complete hosting environment for applications.

## Components

The hosting module integrates the following components:

1. **Naming**: Standardized resource naming based on organization conventions
2. **Networking**: Virtual Network, subnets, and network security groups
3. **Storage Account**: For application and infrastructure data
4. **Key Vault**: For secure storage of secrets and certificates
5. **AKS Cluster**: A managed Kubernetes environment for containerized applications

## Purpose

The purpose of this composite module is to:

- Create a standardized hosting environment across regions
- Maintain consistent configurations between environments
- Simplify deployment of complex infrastructure
- Ensure proper dependencies between components

## Usage

This module should be used as the primary building block for regional deployments. It will create all necessary infrastructure components in a single resource group with proper integration between them.

Example:

```hcl
terraform {
  source = "${get_repo_root()}/infra/live/azure/_modules/hosting"
}

dependency "naming" {
  config_path = "${get_repo_root()}/infra/live/azure/_modules/naming"
  
  mock_outputs = {
    resource_group = "mock-rg"
    storage_account = "mocksa"
    key_vault = "mock-kv"
    vnet = "mock-vnet"
    aks_cluster = "mock-aks"
  }
}

inputs = {
  # Resource group location
  location = "eastus"
  
  # VNet configuration
  address_space = ["10.8.0.0/16"]
  
  # Subnet configuration for your region
  subnets = { ... }
  
  # AKS configuration
  create_aks_cluster = true
  aks_kubernetes_version = "1.28.3"
  # ... other AKS settings
}
```

## Requirements

This module requires you to have:

1. A valid Azure subscription
2. Proper credentials configured for Terraform/Terragrunt
3. Common root Terragrunt configuration
4. Region-specific configuration for subnets, networking, etc.

## Network Guidelines

Each region should use unique CIDR ranges to avoid overlap:

- **East US**: 10.8.0.0/16
- **West US**: 10.9.0.0/16
- **North Europe**: 10.11.0.0/16

Each region should define subnets for:
- Node subnets (for AKS nodes)
- Pod subnets (for AKS pods)
- Endpoint subnets (for private endpoints)
- Shared subnets (gateways, bastion, etc.) 