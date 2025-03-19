# Azure AKS Cluster Composite Module

This module combines multiple specialized AKS modules to create a complete Azure Kubernetes Service (AKS) cluster with all required components and configurations.

## Features

- One-stop solution for complete AKS cluster deployments
- Combines core cluster, identity, networking, and node pool configurations
- Implements best practices for secure and optimized AKS clusters
- Provides unified interface while allowing customization of individual components
- Simplified configuration with sensible defaults

## Usage

```hcl
module "aks_cluster" {
  source = "../../modules/azure/aks_cluster_composite"

  # Basic settings
  resource_group_name = "vip-rg-dev-eus-aks"
  location            = "eastus"
  cluster_name        = "vip-aks-dev-eus-k8s"
  kubernetes_version  = "1.28.3"
  
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
  
  # Identity settings
  identity_type       = "UserAssigned"
  identity_name       = "vip-uami-dev-eus-aks"
  
  # Node pool settings
  default_node_pool = {
    name                = "system"
    vm_size             = "Standard_D4s_v3"
    availability_zones  = [1, 2, 3]
    node_count          = 3
    max_pods            = 30
    os_disk_size_gb     = 128
    os_disk_type        = "Ephemeral"
    os_sku              = "Ubuntu"
    enable_auto_scaling = true
    min_count           = 3
    max_count           = 6
  }
  
  # Additional node pools
  additional_node_pools = {
    app = {
      vm_size             = "Standard_D8s_v3"
      availability_zones  = [1, 2, 3]
      node_count          = 3
      enable_auto_scaling = true
      min_count           = 3
      max_count           = 9
      node_labels = {
        "workload" = "app"
      }
    }
    batch = {
      vm_size             = "Standard_D16s_v3"
      availability_zones  = [1, 2, 3]
      node_count          = 0
      enable_auto_scaling = true
      min_count           = 0
      max_count           = 12
      node_taints = [
        "workload=batch:NoSchedule"
      ]
      node_labels = {
        "workload" = "batch"
      }
    }
  }
  
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
| azuread | >= 2.0.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| resource_group_name | Name of the resource group | `string` | n/a | yes |
| location | Azure region where resources will be created | `string` | n/a | yes |
| cluster_name | Name of the AKS cluster | `string` | n/a | yes |
| kubernetes_version | Kubernetes version | `string` | n/a | yes |
| vnet_id | ID of the virtual network | `string` | n/a | yes |
| subnet_ids | Map of subnet IDs for nodes and pods | `object({ node_subnet_ids = list(string), pod_subnet_ids = optional(list(string)) })` | n/a | yes |
| identity_type | Type of identity to use for the AKS cluster | `string` | `"UserAssigned"` | no |
| identity_name | Name of the user assigned identity (required when identity_type is UserAssigned) | `string` | `null` | no |
| create_identity | Whether to create a new user assigned identity | `bool` | `true` | no |
| existing_identity_id | ID of an existing user assigned identity | `string` | `null` | no |
| default_node_pool | Configuration for the default node pool | `any` | See variables.tf | yes |
| additional_node_pools | Map of additional node pools to create | `map(any)` | `{}` | no |
| network_plugin | Network plugin to use (azure, kubenet, none) | `string` | `"azure"` | no |
| network_policy | Network policy to use (calico, azure) | `string` | `"calico"` | no |
| service_cidr | CIDR range for Kubernetes services | `string` | `"10.96.0.0/16"` | no |
| dns_service_ip | IP address for Kubernetes DNS service | `string` | `"10.96.0.10"` | no |
| outbound_type | Outbound traffic type | `string` | `"loadBalancer"` | no |
| enable_workload_identity | Whether to enable workload identity | `bool` | `false` | no |
| private_cluster_enabled | Whether to create a private cluster | `bool` | `false` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the AKS cluster |
| name | The name of the AKS cluster |
| kubernetes_version | The Kubernetes version used |
| fqdn | The FQDN of the AKS cluster |
| private_fqdn | The private FQDN of the AKS cluster |
| kube_config | The kubeconfig for the AKS cluster |
| node_resource_group | The auto-generated resource group for cluster resources |
| identity_principal_id | The principal ID of the AKS cluster identity |
| kubelet_identity | The kubelet managed identity |
| oidc_issuer_url | The OIDC issuer URL for the cluster |

## Additional Resources

For more information on each specialized module, refer to their individual documentation:

- [AKS Core Module](../aks_core/README.md)
- [AKS Identity Module](../aks_identity/README.md)
- [AKS Networking Module](../aks_networking/README.md)
- [AKS Node Pools Module](../aks_node_pools/README.md)

## License

This module is proprietary and confidential.

## Authors

VIP Platform Team 