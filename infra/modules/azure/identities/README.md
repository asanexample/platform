# Azure Identities Module

This module provides a unified approach to managing Azure identities for AKS clusters and workloads. It eliminates the need for a two-phase deployment approach by handling both AKS cluster identities and workload identities in a single, coherent module.

## Features

- Creates user-assigned managed identities for AKS clusters
- Creates workload identities with proper service account bindings
- Sets up federated credentials for workload identities
- Manages role assignments for networking, route tables, and other Azure resources
- Supports conditional creation of resources based on configuration flags

## Usage

### Basic AKS Identity

```hcl
module "identities" {
  source = "../identities"

  prefix      = "centric"
  customer    = "example"
  stage       = "dev"
  region_abbv = "eus"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  
  cluster_name = "my-aks-cluster"
  create_aks_identity = true
  
  tags = {
    Environment = "Development"
  }
}
```

### Workload Identities with OIDC

```hcl
module "identities" {
  source = "../identities"

  prefix      = "centric"
  customer    = "example"
  stage       = "dev"
  region_abbv = "eus"

  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  
  cluster_name = "my-aks-cluster"
  create_aks_identity = true
  
  # Workload identity configuration
  enable_workload_identity = true
  aks_oidc_issuer_url = "https://oidc-issuer-url"
  node_resource_group_id = "/subscriptions/.../resourceGroups/MC_..."
  
  workload_identities = {
    "cert-manager" = {
      namespace       = "cert-manager"
      service_account = "cert-manager"
      roles           = ["DNS Zone Contributor"]
    },
    "karpenter" = {
      namespace       = "karpenter"
      service_account = "karpenter"
      roles           = ["Virtual Machine Contributor", "Network Contributor"]
    }
  }
  
  tags = {
    Environment = "Development"
  }
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| prefix | Naming prefix for resources | `string` | `""` | no |
| customer | Customer name for resource naming | `string` | n/a | yes |
| stage | Stage/environment name (e.g., dev, qa, prod) | `string` | n/a | yes |
| region_abbv | Region abbreviation for naming purposes | `string` | `""` | no |
| resource_group_name | Name of the resource group | `string` | n/a | yes |
| location | Azure region | `string` | n/a | yes |
| cluster_name | Name of the AKS cluster | `string` | `null` | no |
| create_aks_identity | Whether to create an identity for the AKS cluster | `bool` | `true` | no |
| aks_identity_name | Custom name for the AKS identity | `string` | `null` | no |
| vnet_resource_group_name | Name of the resource group containing the VNet | `string` | `null` | no |
| private_route_table_name | Name of the private route table | `string` | `null` | no |
| subnet_id | ID of the subnet | `string` | `null` | no |
| enable_workload_identity | Whether to enable workload identity | `bool` | `false` | no |
| aks_oidc_issuer_url | OIDC issuer URL of the AKS cluster | `string` | `null` | no |
| node_resource_group_id | ID of the node resource group | `string` | `null` | no |
| workload_identities | Map of workload identities to create | `map(object)` | `{}` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
|------|-------------|
| aks_identity_id | ID of the AKS identity |
| aks_identity_principal_id | Principal ID of the AKS identity |
| aks_identity_client_id | Client ID of the AKS identity |
| workload_identities | Map of all workload identities created |
| cert_manager_identity | Details of the cert-manager identity if created |
| karpenter_identity | Details of the Karpenter identity if created |
| federated_identity_credentials | Map of all federated identity credentials created |

## Testing

The module includes tests to verify functionality. Run tests using:

```bash
cd infra/tests/modules/azure/identities
terraform init
terraform test
``` 