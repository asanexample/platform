# Azure Networking for West US

This Terragrunt configuration deploys a virtual network with subnets for our Azure infrastructure in the West US region.

## Configuration Overview

The networking configuration creates a multi-zone virtual network architecture optimized for AKS and supporting services:

- **Virtual Network**: Address space of `10.9.0.0/16`
- **Subnet Structure**:
  - AZ1, AZ2, and AZ3 zonal subnets for node pools, pods, and private endpoints
  - Shared subnets for gateway and bastion services
- **AKS Networking Integration**:
  - Dedicated NSG rules for AKS node subnets
  - Private DNS zone for private AKS clusters
  - Proper network isolation for cluster components

## Recent Changes

### Consolidated AKS Networking

The AKS networking configuration has been consolidated into the main networking module, eliminating the need for a separate `aks_networking` module. This provides several benefits:

- **Simplified Architecture**: All networking concerns are managed in a single module
- **Eliminated Conflicts**: Resolved the conflict with multiple resources trying to manage the same subnet NSG associations
- **Better Dependency Management**: Clearer dependency chain for AKS and related resources

The previous `aks_networking` module has been deprecated and should not be used.

## Dependencies

- **Resource Group**: Uses the existing resource group
- **Naming Module**: Gets standardized resource names from the naming module

## Network Subnets

| Subnet Name | CIDR Range | Purpose |
|-------------|------------|---------|
| az1-node-subnet | 10.9.0.0/20 | AKS worker nodes in AZ1 |
| az1-pod-subnet | 10.9.16.0/20 | AKS pods in AZ1 |
| az1-endpoint-subnet | 10.9.32.0/24 | Private endpoints in AZ1 |
| az2-node-subnet | 10.9.64.0/20 | AKS worker nodes in AZ2 |
| az2-pod-subnet | 10.9.80.0/20 | AKS pods in AZ2 |
| az2-endpoint-subnet | 10.9.96.0/24 | Private endpoints in AZ2 |
| az3-node-subnet | 10.9.128.0/20 | AKS worker nodes in AZ3 |
| az3-pod-subnet | 10.9.144.0/20 | AKS pods in AZ3 |
| az3-endpoint-subnet | 10.9.160.0/24 | Private endpoints in AZ3 |
| gateway-subnet | 10.9.192.0/24 | Application gateway |
| bastion-subnet | 10.9.193.0/24 | Azure Bastion |

## AKS Networking Configuration

The configuration enables AKS-specific networking features:

```hcl
# AKS Networking Configuration
enable_aks_networking = true
aks_subnet_name = "az1-node-subnet"
aks_cluster_name = dependency.naming.outputs.aks_cluster
aks_private_cluster_enabled = true
aks_node_resource_group = "${dependency.resource_group.outputs.name}-nodes"
```

This creates:
- AKS-specific NSG rules for the node subnet
- A private DNS zone for AKS (`privatelink.westus.azmk8s.io`)
- A virtual network link for the private DNS zone

## Applying Changes

To apply changes to this configuration:

```bash
cd infra/live/azure/dev/westus/networking
terragrunt apply
```

## Outputs

After deployment, you can access various outputs, including:

- `vnet_id`: The ID of the virtual network
- `subnet_ids`: Map of subnet names to subnet IDs
- `aks_subnet_id`: The ID of the subnet used for AKS nodes
- `aks_private_dns_zone_id`: The ID of the AKS private DNS zone
- `private_endpoints_subnet_id`: The ID of the private endpoints subnet

These outputs are used by other modules as dependencies. 