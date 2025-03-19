# Network CIDR Allocations

This document provides guidance on network CIDR allocations based on the reference file `allocations.csv`. All network configurations should adhere to these allocations to maintain consistent network topology across environments.

## Using the Allocations CSV File

The `allocations.csv` file is the source of truth for CIDR allocations across all cloud providers, regions, and availability zones. When implementing network configurations:

1. Always refer to this file to determine the correct CIDR blocks for your region
2. Match subnet naming and CIDR allocations exactly as specified
3. Use the appropriate subnet types (Kubernetes, Services, Endpoints, Transit) with their allocated CIDRs

## Azure CIDR Allocation Structure

For Azure regions, the CIDR allocations follow this hierarchy:

- **Cloud Provider Block**: `10.101.0.0/16` for Azure
- **Region Block**: Each region gets a `/21` allocation within the cloud provider block
- **Availability Zone**: Each AZ gets a `/24` allocation within the region block
- **Subnet Types**: Each AZ has specific allocations for subnet purposes:
  - **Kubernetes**: `/26` subnet for Kubernetes nodes
  - **Services**: `/27` subnet for application services
  - **Endpoints**: `/28` subnet for private endpoints
  - **Transit**: `/29` subnet for transit connectivity

## Region CIDR Map

| Region | VNET CIDR | Notes |
|--------|-----------|-------|
| eastus | 10.101.0.0/21 | East US |
| eastus2 | 10.101.8.0/21 | East US 2 |
| centralus | 10.101.16.0/21 | Central US |
| westus | 10.101.24.0/21 | West US |
| westus2 | 10.101.32.0/21 | West US 2 |
| westus3 | 10.101.40.0/21 | West US 3 |
| canadacentral | 10.101.48.0/21 | Canada Central |
| brazilsouth | 10.101.56.0/21 | Brazil South |
| westeurope | 10.101.64.0/21 | West Europe |
| northeurope | 10.101.72.0/21 | North Europe |
| uksouth | 10.101.80.0/21 | UK South |

## Subnet Structure Per Region

For each region, the subnet structure should follow this pattern (using westus as an example):

### Availability Zone 1

| Subnet Name | CIDR Block | Purpose | Service Endpoints |
|-------------|------------|---------|-------------------|
| az1-kubernetes | 10.101.24.0/26 | Kubernetes nodes | Storage, KeyVault, ContainerRegistry |
| az1-services | 10.101.24.64/27 | Services | Storage, KeyVault, SQL |
| az1-endpoints | 10.101.24.96/28 | Private endpoints | Storage, SQL, KeyVault |
| az1-transit | 10.101.24.112/29 | Transit connectivity | Storage |

### Availability Zone 2

| Subnet Name | CIDR Block | Purpose | Service Endpoints |
|-------------|------------|---------|-------------------|
| az2-kubernetes | 10.101.25.0/26 | Kubernetes nodes | Storage, KeyVault, ContainerRegistry |
| az2-services | 10.101.25.64/27 | Services | Storage, KeyVault, SQL |
| az2-endpoints | 10.101.25.96/28 | Private endpoints | Storage, SQL, KeyVault |
| az2-transit | 10.101.25.112/29 | Transit connectivity | Storage |

### Availability Zone 3

| Subnet Name | CIDR Block | Purpose | Service Endpoints |
|-------------|------------|---------|-------------------|
| az3-kubernetes | 10.101.26.0/26 | Kubernetes nodes | Storage, KeyVault, ContainerRegistry |
| az3-services | 10.101.26.64/27 | Services | Storage, KeyVault, SQL |
| az3-endpoints | 10.101.26.96/28 | Private endpoints | Storage, SQL, KeyVault |
| az3-transit | 10.101.26.112/29 | Transit connectivity | Storage |

## Implementation Guidelines

When implementing network configurations in Terraform/Terragrunt:

1. Reference this document and the allocations.csv file
2. Use the terragrunt.hcl file template for consistency
3. Ensure all subnet names and CIDR blocks match exactly
4. Configure the correct service endpoints for each subnet
5. Set proper dependencies on resource groups and naming

Example networking configuration in Terragrunt:

```hcl
# VNet configuration
vnet_name = dependency.naming.outputs.virtual_network
address_space = ["10.101.24.0/21"]  # Westus region CIDR per allocations.csv

# Subnets following allocations.csv
subnets = {
  # AZ1 (westus-1) subnets
  "az1-kubernetes" = {
    address_prefixes  = ["10.101.24.0/26"]
    service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.ContainerRegistry"]
  },
  "az1-services" = {
    address_prefixes  = ["10.101.24.64/27"]
    service_endpoints = ["Microsoft.Storage", "Microsoft.KeyVault", "Microsoft.Sql"]
  },
  "az1-endpoints" = {
    address_prefixes  = ["10.101.24.96/28"]
    service_endpoints = ["Microsoft.Storage", "Microsoft.Sql", "Microsoft.KeyVault"]
  },
  "az1-transit" = {
    address_prefixes  = ["10.101.24.112/29"]
    service_endpoints = ["Microsoft.Storage"]
  },
  # ... other subnets ...
}
```

## AKS Network Integration

When configuring AKS networking, use the appropriate Kubernetes subnet:

```hcl
# AKS Networking Configuration
enable_aks_networking = true
aks_subnet_name = "az1-kubernetes"
aks_cluster_name = dependency.naming.outputs.aks_cluster
aks_private_cluster_enabled = true
```

## Network Security Considerations

- Each subnet will have a Network Security Group (NSG) automatically created
- Add custom NSG rules as needed based on the subnet's purpose
- Endpoints subnets should be highly restricted for private endpoint access only
- Transit subnets should only allow necessary cross-network traffic 