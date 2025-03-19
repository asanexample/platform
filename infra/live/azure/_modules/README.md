# Azure Terragrunt Module Structure

This directory contains the Terragrunt configuration for reusable modules that compose our Azure infrastructure. These modules are organized to create a clean dependency structure and promote reusability.

## Module Organization

The modules are organized in a hierarchical manner:

- **Base/Primitive Modules**: Located at `infra/modules/azure/` 
- **Terragrunt Module Wrappers**: Located in this directory (`infra/live/azure/_modules/`)
- **Environment-Specific Implementations**: Located in `infra/live/azure/<env>/<region>/`

## Module Dependencies

The module dependencies are structured as follows:

```
naming
  ↑
  ├─ networking 
  ├─ storage_account
  ├─ key_vault
  ├─ aks_cluster_composite
  │     ↑
  hosting (depends on all above)
```

## Modules

### naming
The foundational module that provides consistent resource naming according to organizational standards.

### networking
Creates the VNet and subnet infrastructure.

### storage_account
Creates storage accounts, containers, and network rules.

### key_vault
Creates key vaults with optional private endpoints.

### aks_cluster_composite
Creates an AKS cluster with supporting resources like identities and node pools.

### hosting
A composite module that integrates all of the above components into a complete hosting infrastructure.

## Using These Modules

To use these modules in your environment, reference them in your Terragrunt configuration:

```hcl
terraform {
  source = "${get_repo_root()}/infra/live/azure/_modules/hosting"
}

# Set dependencies for the naming module
dependency "naming" {
  config_path = "${get_repo_root()}/infra/live/azure/_modules/naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group = "mock-rg"
    storage_account = "mocksa"
    key_vault = "mock-kv"
    vnet = "mock-vnet"
    aks_cluster = "mock-aks"
  }
}
```

## Best Practices

1. Always use mock outputs in your dependency blocks to support planning and validation operations.
2. Use `find_in_parent_folders()` to include common configurations.
3. Use region-specific variables like `address_space` to maintain isolation between regions.
4. Reference modules using `${get_repo_root()}/...` patterns for consistent path resolution. 