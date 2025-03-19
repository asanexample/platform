# CIDR Allocation Strategy

This document outlines the hierarchical CIDR allocation strategy used for the multi-cloud platform infrastructure, ensuring clear network boundaries and preventing IP address conflicts.

## Hierarchical Design

The CIDR allocation follows a hierarchical approach:

```
Global Address Space
├── Cloud Provider
│   ├── Environment
│   │   ├── Region
│   │   │   ├── Availability Zone
│   │   │   │   └── Subnet Purpose
```

## Global Address Space Allocation

| Network Level | CIDR Block | Description |
|---------------|------------|-------------|
| Global | 10.0.0.0/8 | Complete address space for all environments |

## Cloud Provider Allocation

| Cloud Provider | CIDR Block | Description |
|----------------|------------|-------------|
| Azure | 10.0.0.0/10 | Azure resources (10.0.0.0 - 10.63.255.255) |
| AWS | 10.64.0.0/10 | AWS resources (10.64.0.0 - 10.127.255.255) |
| GCP | 10.128.0.0/10 | GCP resources (10.128.0.0 - 10.191.255.255) |
| On-premises | 10.192.0.0/10 | On-premises and future expansion (10.192.0.0 - 10.255.255.255) |

## Environment Allocation (Azure Example)

| Environment | CIDR Block | Description |
|-------------|------------|-------------|
| Shared | 10.0.0.0/13 | Shared infrastructure (10.0.0.0 - 10.7.255.255) |
| Development | 10.8.0.0/13 | Development environment (10.8.0.0 - 10.15.255.255) |
| Pre-production | 10.16.0.0/13 | Pre-production/staging (10.16.0.0 - 10.23.255.255) |
| Production | 10.24.0.0/13 | Production environment (10.24.0.0 - 10.31.255.255) |
| Demo | 10.32.0.0/13 | Demo environment (10.32.0.0 - 10.39.255.255) |
| Reserved | 10.40.0.0/11 | Reserved for future use (10.40.0.0 - 10.63.255.255) |

## Regional Allocation (Azure Development Example)

| Region | CIDR Block | Description |
|--------|------------|-------------|
| East US | 10.8.0.0/16 | Development in East US |
| West US | 10.9.0.0/16 | Development in West US |
| North Europe | 10.10.0.0/16 | Development in North Europe |
| West Europe | 10.11.0.0/16 | Development in West Europe |

## Availability Zone Allocation (Azure Development East US Example)

| Availability Zone | CIDR Block | Description |
|-------------------|------------|-------------|
| Zone 1 | 10.8.0.0/18 | Resources in AZ1 |
| Zone 2 | 10.8.64.0/18 | Resources in AZ2 |
| Zone 3 | 10.8.128.0/18 | Resources in AZ3 |
| Cross-zone | 10.8.192.0/18 | Resources across multiple zones |

## Subnet Allocation (Azure Development East US Zone 1 Example)

| Subnet Purpose | CIDR Block | Size | Description |
|----------------|------------|------|-------------|
| AKS Node Subnet | 10.8.0.0/20 | /20 (4,096 IPs) | Kubernetes node subnet |
| AKS Pod Subnet | 10.8.16.0/20 | /20 (4,096 IPs) | Kubernetes pod subnet |
| Private Endpoints | 10.8.32.0/24 | /24 (256 IPs) | Azure private endpoints |
| Gateway | 10.8.33.0/24 | /24 (256 IPs) | Application gateway |
| Load Balancer | 10.8.34.0/24 | /24 (256 IPs) | Azure load balancer |
| Reserved | 10.8.35.0/21 | /21 (2,048 IPs) | Reserved for future use |

## Implementation in Terraform

```hcl
# Example VNet Configuration
resource "azurerm_virtual_network" "example" {
  name                = "vip-vnet-dev-eus-main"
  location            = "eastus"
  resource_group_name = azurerm_resource_group.example.name
  address_space       = ["10.8.0.0/16"]  # East US Dev
  
  tags = {
    Environment     = "dev"
    CIDRHierarchy   = "Azure-Dev-EastUS"
    NetworkDesign   = "Kubernetes3AZ"
  }
}

# Example Subnet Configuration for AZ1
resource "azurerm_subnet" "az1_node" {
  name                 = "az1-node-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.8.0.0/20"]
}

resource "azurerm_subnet" "az1_pods" {
  name                 = "az1-pods-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.8.16.0/20"]
}

resource "azurerm_subnet" "az1_endpoints" {
  name                 = "az1-endpoints-subnet"
  resource_group_name  = azurerm_resource_group.example.name
  virtual_network_name = azurerm_virtual_network.example.name
  address_prefixes     = ["10.8.32.0/24"]
}
```

## Network Connectivity Considerations

1. **VNet Peering**: When connecting different virtual networks, ensure CIDR ranges don't overlap
2. **Hub and Spoke**: Regional hub networks use dedicated address spaces separate from workload spokes
3. **On-premises Connectivity**: Reserved specific blocks for on-premises networks to avoid conflicts
4. **Transit Networks**: Dedicated transit networks use the cross-zone address space

## Special Considerations

1. **Multi-region Deployments**: Each region has its own dedicated address space
2. **Expansion Planning**: Large reserved spaces allow for future growth
3. **Subnet Sizing**: Subnets are sized based on expected resource counts with room for growth
4. **Network Security Groups**: NSGs applied at subnet level with appropriate rules
5. **Service Endpoints**: Configured for storage, Key Vault, and databases

## Implementation Guidelines

1. Always reference this document when allocating new networks
2. Document any deviations from the standard allocation
3. Reserve larger CIDR blocks than immediately needed to allow for expansion
4. Use descriptive tags to identify networks according to this hierarchy
5. Run IP overlap detection before creating new networks

## Change Management

Changes to the CIDR allocation strategy must be carefully managed to avoid disruption:

1. Proposed changes must be documented and reviewed
2. Changes should be implemented incrementally
3. CIDR changes may require recreation of network resources
4. Always maintain this document when changes are implemented 