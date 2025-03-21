# Region Template

This directory contains template files for setting up a new Azure region. Copy this directory structure to create a new region under a specific environment.

## Steps to Create a New Region

1. Copy this directory to the target environment (e.g., `infra/live/azure/dev/eastus/`)
2. Update `region.hcl` with the appropriate region name and region_abbv
3. Update `network.hcl` with the correct CIDR blocks for your new region
4. Make any region-specific adjustments needed in the module folders

## Module Deployment Order

Modules should be deployed in the following order:

1. naming
2. resource_group
3. networking
4. aks_identity
5. storage
6. key_vault
7. aks_core
8. aks_node_pools
9. cilium 