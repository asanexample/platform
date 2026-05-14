# AKS Identity Module

Creates user-assigned managed identities for AKS clusters, including optional workload identities for cert-manager and Karpenter.

## Usage

```hcl
module "aks_identity" {
  source = "../aks_identity"

  create              = true
  resource_group_name = module.resource_group.name
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"

  cluster_name              = module.aks_core.name
  oidc_issuer_url           = module.aks_core.oidc_issuer_url
  node_resource_group_id    = module.aks_core.node_resource_group_id
  create_workload_identities = true

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "aks_identity" {
  source = "../aks_identity"

  create              = false
  resource_group_name = "placeholder"
  location            = "eastus"
  cluster_name        = "placeholder"
}
```

### Cluster identity only (no workload identities)

```hcl
module "aks_identity" {
  source = "../aks_identity"

  create              = true
  resource_group_name = module.resource_group.name
  location            = "eastus"
  cluster_name        = "aks-platform-dev-eus"

  create_workload_identities = false

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_role_assignment.aks_network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aks_subnet_network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kubelet_managed_identity_operator](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.aks_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.cert_manager_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.karpenter_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| cluster_name | The name of the AKS cluster the identities are for | `string` | n/a | yes |
| location | The Azure location where the identities will be deployed | `string` | n/a | yes |
| resource_group_name | The resource group name where the identities will be created | `string` | n/a | yes |
| aks_identity_name | The name of the user-assigned managed identity for AKS | `string` | `null` | no |
| cert_manager_federated_credential_name | The name of the cert-manager federated credential. If not provided, a name will be generated. | `string` | `null` | no |
| cert_manager_identity_name | The name of the cert-manager identity. If not provided, a name will be generated. | `string` | `null` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| create_workload_identities | Whether to create workload identities for common services like cert-manager and karpenter | `bool` | `false` | no |
| environment | The environment (e.g. dev, test, prod) | `string` | `"dev"` | no |
| karpenter_federated_credential_name | The name of the karpenter federated credential. If not provided, a name will be generated. | `string` | `null` | no |
| karpenter_identity_name | The name of the karpenter identity. If not provided, a name will be generated. | `string` | `null` | no |
| node_resource_group_id | The ID of the node resource group created by AKS | `string` | `null` | no |
| oidc_issuer_enabled | Whether OIDC issuer is enabled on the AKS cluster | `bool` | `false` | no |
| oidc_issuer_url | The OIDC issuer URL of the AKS cluster | `string` | `null` | no |
| workload | The workload name to use for all resources | `string` | `"platform"` | no |
| private_route_table_name | The name of the private route table used by the AKS cluster | `string` | `null` | no |
| region_abbv | The abbreviated region name | `string` | `"weu"` | no |
| subnet_id | The ID of the subnet where the AKS cluster is deployed | `string` | `null` | no |
| tags | Tags to apply to all resources | `map(string)` | `{}` | no |
| vnet_resource_group_name | The resource group name containing the VNet and route table | `string` | `null` | no |
| workload_identity_enabled | Whether workload identity is enabled on the AKS cluster | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| aks_identity_client_id | The client ID of the AKS cluster identity |
| aks_identity_id | The ID of the AKS cluster identity |
| aks_identity_principal_id | The principal ID of the AKS cluster identity |
| cert_manager_identity_client_id | The client ID of the cert-manager identity |
| cert_manager_identity_id | The ID of the cert-manager identity |
| cert_manager_identity_principal_id | The principal ID of the cert-manager identity |
| create | Whether resources were created |
| karpenter_identity_client_id | The client ID of the karpenter identity |
| karpenter_identity_id | The ID of the karpenter identity |
| karpenter_identity_principal_id | The principal ID of the karpenter identity |
<!-- END_TF_DOCS -->

## Dependencies

- [resource_group](../resource_group) -- resource group where identities are created
- [aks_core](../aks_core) -- provides OIDC issuer URL and node resource group ID for federated credentials

## Notes

- Workload identities for cert-manager and Karpenter are created when `create_workload_identities = true`.
- Federated credentials require the AKS cluster's OIDC issuer URL, so the cluster must exist before creating workload identities.
