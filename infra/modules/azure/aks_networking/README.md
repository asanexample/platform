# ⚠️ DEPRECATED - AKS Networking Module

> **Important**: This module has been deprecated and its functionality has been consolidated into the main `networking` module. Please use the enhanced networking module instead.

## Migration Guide

To migrate from this module to the enhanced networking module:

1. Update your terraform sources to point to the networking module
2. Use the new AKS-specific parameters in the networking module:

```hcl
module "networking" {
  source = "../../modules/azure/networking"
  
  # Regular networking parameters...
  
  # AKS Networking Parameters (replaces the aks_networking module)
  enable_aks_networking = true
  aks_subnet_name = "your-aks-subnet-name"
  aks_cluster_name = "your-aks-cluster-name"
  aks_private_cluster_enabled = true
  aks_node_resource_group = "your-node-resource-group"
}
```

## Why This Module is Deprecated

This module was deprecated because:

1. It caused resource conflicts with the main networking module
2. Having networking logic split across multiple modules was causing confusion
3. The Single Responsibility Principle suggests networking concerns should be consolidated

## Original Documentation (For Reference Only)

This module configures network resources and settings for Azure Kubernetes Service (AKS) clusters, implementing secure and optimized networking for Kubernetes workloads.

## Features

- Configures Azure CNI networking for AKS clusters
- Sets up pod and node networking with dedicated subnets
- Implements network policies and security configurations
- Configures DNS settings and service CIDR ranges
- Supports advanced networking features and private clusters

## Usage

```hcl
module "aks_networking" {
  source = "../../modules/azure/aks_networking"

  # Basic settings
  resource_group_name = "vip-rg-dev-eus-aks"
  location            = "eastus"
  
  # Network settings
  vnet_id             = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-net/providers/Microsoft.Network/virtualNetworks/vip-vnet-dev-eus-main"
  subnet_ids = {
    node_subnet_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-net/providers/Microsoft.Network/virtualNetworks/vip-vnet-dev-eus-main/subnets/az1-node-subnet",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-net/providers/Microsoft.Network/virtualNetworks/vip-vnet-dev-eus-main/subnets/az2-node-subnet",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-net/providers/Microsoft.Network/virtualNetworks/vip-vnet-dev-eus-main/subnets/az3-node-subnet"
    ]
    pod_subnet_ids = [
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-net/providers/Microsoft.Network/virtualNetworks/vip-vnet-dev-eus-main/subnets/az1-pod-subnet",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-net/providers/Microsoft.Network/virtualNetworks/vip-vnet-dev-eus-main/subnets/az2-pod-subnet",
      "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-net/providers/Microsoft.Network/virtualNetworks/vip-vnet-dev-eus-main/subnets/az3-pod-subnet"
    ]
  }
  
  # Network configuration
  network_plugin      = "azure"
  network_policy      = "calico"
  service_cidr        = "10.96.0.0/16"
  dns_service_ip      = "10.96.0.10"
  outbound_type       = "loadBalancer"
  
  # Tags
  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
    Component   = "AKS"
  }
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | >= 3.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | Name of the resource group | `string` | n/a | yes |
| location | Azure region where resources will be created | `string` | n/a | yes |
| vnet_id | ID of the virtual network | `string` | n/a | yes |
| subnet_ids | Map of subnet IDs for nodes and pods | `object({ node_subnet_ids = list(string), pod_subnet_ids = optional(list(string)) })` | n/a | yes |
| network_plugin | Network plugin to use for Kubernetes networking (azure, kubenet, none) | `string` | `"azure"` | no |
| network_plugin_mode | Network plugin mode when using Azure CNI (overlay or transparent) | `string` | `null` | no |
| network_policy | Network policy to use (calico, azure) | `string` | `"calico"` | no |
| service_cidr | CIDR range for Kubernetes services | `string` | `"10.96.0.0/16"` | no |
| dns_service_ip | IP address for Kubernetes DNS service | `string` | `"10.96.0.10"` | no |
| docker_bridge_cidr | CIDR range for the Docker bridge network | `string` | `"172.17.0.1/16"` | no |
| outbound_type | Outbound traffic type (loadBalancer, userDefinedRouting, managedNATGateway, userAssignedNATGateway) | `string` | `"loadBalancer"` | no |
| load_balancer_sku | SKU of the Azure Load Balancer (basic or standard) | `string` | `"standard"` | no |
| private_cluster_enabled | Whether to create a private cluster | `bool` | `false` | no |
| private_dns_zone_id | ID of the private DNS zone when private cluster is enabled | `string` | `null` | no |
| private_cluster_public_fqdn_enabled | Whether to enable public FQDN for private clusters | `bool` | `false` | no |
| nat_gateway_id | ID of an existing NAT gateway | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| network_plugin | The network plugin used for the AKS cluster |
| network_policy | The network policy used for the AKS cluster |
| network_plugin_mode | The network plugin mode used for the AKS cluster |
| service_cidr | The CIDR range for Kubernetes services |
| dns_service_ip | The IP address for Kubernetes DNS service |
| outbound_type | The outbound traffic configuration type |
| node_subnet_ids | List of subnet IDs used for nodes |
| pod_subnet_ids | List of subnet IDs used for pods |
| vnet_id | The ID of the virtual network |
| load_balancer_profile | The load balancer profile configuration |
| load_balancer_sku | The SKU of the Azure Load Balancer |
| private_cluster_enabled | Whether the cluster is a private cluster |
| private_dns_zone_id | The ID of the private DNS zone |

## Network Plugin Options

This module supports different networking configurations for AKS clusters:

1. **Azure CNI (network_plugin = "azure")**:
   - Provides direct integration with Azure networking
   - Each pod gets an IP address from the subnet
   - Supports advanced features like network policies
   - Requires larger subnets due to IP allocation for every pod

2. **Kubenet (network_plugin = "kubenet")**:
   - Basic Kubernetes network implementation
   - Uses network address translation (NAT) for pod connectivity
   - More efficient IP usage but with some limitations
   - Limited support for certain features

3. **None (network_plugin = "none")**:
   - For custom CNI implementations
   - Allows installation of alternative CNI plugins (like Cilium, Antrea)
   - Requires manual configuration of networking post-cluster creation

## Network Policy Options

Network policies control pod-to-pod traffic:

1. **Calico (network_policy = "calico")**:
   - Open-source network policy implementation
   - Supports complex network policies with enhanced functionality
   - Works with both Azure CNI and kubenet

2. **Azure (network_policy = "azure")**:
   - Azure's native network policy implementation
   - Simpler but with fewer features than Calico
   - Only compatible with Azure CNI

## Private Cluster Configuration

To create a private AKS cluster:

```hcl
module "aks_networking" {
  source = "../../modules/azure/aks_networking"
  
  # Basic settings
  resource_group_name = "vip-rg-dev-eus-aks"
  location            = "eastus"
  
  # Network settings (same as before)
  
  # Private cluster settings
  private_cluster_enabled = true
  private_dns_zone_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/vip-rg-dev-eus-dns/providers/Microsoft.Network/privateDnsZones/privatelink.eastus.azmk8s.io"
}
```

## Integration with Other Modules

This module is designed to work with:

- [AKS Core Module](../aks_core/README.md): Provides the main AKS cluster configuration
- [AKS Cluster Module](../aks_cluster/README.md): Combines multiple AKS modules
- [AKS Cluster Composite Module](../aks_cluster_composite/README.md): Higher-level abstraction for AKS deployment
- [Networking Module](../networking/README.md): Creates the underlying VNet and subnet infrastructure

## License

This module is proprietary and confidential.

## Authors

VIP Platform Team 