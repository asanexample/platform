# eastus Region Infrastructure (azure)

This directory contains the infrastructure configuration for the eastus region in the dev environment for azure.

## Modules

The following modules are deployed in this region:
- `aks_core`
- `aks_identity`
- `aks_node_pools`
- `key_vault`
- `naming`
- `networking`
- `resource_group`
- `storage`

## CIDR Range

The eastus region uses the CIDR range: `10.101.0.0/21`

## Deployment Order

Modules should be deployed in the following order:

1. resource_group
2. naming
3. networking
4. key_vault
5. storage
6. aks_identity
7. aks_core
8. aks_node_pools

## Generated Configuration

This directory was scaffolded from templates on Wed Mar 19 23:48:28 PDT 2025.
