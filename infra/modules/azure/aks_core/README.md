# AKS Core Module

This module creates the essential components of an Azure Kubernetes Service (AKS) cluster, focusing solely on the core cluster functionality without additional features. It uses the common naming module to ensure consistent naming conventions across all resources.

## Features

- Creates a basic AKS cluster with minimal configuration
- Uses standardized naming conventions via the naming module
- Provides flexible identity configurations (System or User Assigned)
- Configurable default node pool settings
- Support for workload identity and OIDC issuer configuration
- Azure Policy and cost analysis enabled by default

## Usage

```hcl
module "aks_core" {
  source = "../modules/azure/aks_core"

  # Naming
  prefix      = "vip"
  stage       = "dev"
  region_abbv = "eus"
  
  # Resource details
  resource_group_name = "rg-aks-dev-001"
  location           = "eastus"
  dns_prefix         = "aks-dev"
  
  # Identity (using System Assigned for simplicity)
  identity_type = "SystemAssigned"
  
  # Default node pool configuration
  default_nodepool_name    = "system"
  default_nodepool_vm_size = "Standard_D2s_v4"
  default_nodepool_count   = 1

  # Enabling workload identity and OIDC issuer for modern authentication
  workload_identity_enabled = true
  oidc_issuer_enabled       = true

  # Tags
  tags = {
    Environment = "Development"
    ManagedBy   = "Terraform"
  }
}
```

## Dependencies

This module depends on:
- The Azure naming module for resource naming

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.3.0 |
| azurerm | 4.23.0 |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | Prefix to use for resource names | `string` | `"vip"` | no |
| customer | Customer name for resource naming | `string` | `null` | no |
| stage | Environment stage (dev, preprod, prod, test, stg) | `string` | n/a | yes |
| region_abbv | Abbreviated Azure region name | `string` | n/a | yes |
| name | Custom name for the AKS cluster | `string` | `""` | no |
| resource_group_name | Resource group name | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| dns_prefix | DNS prefix for the cluster | `string` | `null` | no |
| kubernetes_version | Kubernetes version | `string` | `null` | no |
| local_account_disabled | Disable local accounts | `bool` | `true` | no |
| sku_tier | SKU tier (Free or Standard) | `string` | `"Free"` | no |
| workload_identity_enabled | Enable workload identity | `bool` | `true` | no |
| oidc_issuer_enabled | Enable OIDC issuer | `bool` | `true` | no |
| default_nodepool_name | Default node pool name | `string` | `"system"` | no |
| default_nodepool_vm_size | Default node pool VM size | `string` | `"Standard_D2s_v4"` | no |
| default_nodepool_count | Default node pool node count | `number` | `1` | no |
| identity_type | Identity type (SystemAssigned or UserAssigned) | `string` | `"UserAssigned"` | no |
| user_assigned_identity_id | User-assigned identity ID | `string` | `null` | no |
| tags | Resource tags | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| id | The ID of the AKS cluster |
| name | The name of the AKS cluster |
| resource_group_name | The resource group name |
| location | The cluster location |
| kubernetes_version | The Kubernetes version |
| kube_config_raw | Raw Kubernetes config for authentication |
| host | The Kubernetes host |
| client_certificate | Client certificate for authentication |
| client_key | Client key for authentication |
| cluster_ca_certificate | CA certificate for authentication |
| default_node_pool_id | Default node pool ID |
| node_resource_group | Node resource group name |
| oidc_issuer_url | OIDC issuer URL |
| kubelet_identity | Kubelet managed identity |
| identity | Cluster identity |
| fqdn | Cluster FQDN |

## Notes

- This module is designed to be used with other specialized AKS modules for a complete solution
- For more advanced configurations, use this with the AKS node pools, identity, networking, and monitoring modules
- The default node pool configuration is minimal to encourage separation of concerns 