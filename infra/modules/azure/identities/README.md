# Azure Identities Module

Creates user-assigned managed identities and federated credentials for AKS clusters and workloads.

## Usage

```hcl
module "identities" {
  source = "../identities"

  create              = true
  resource_group_name = module.resource_group.name
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"

  cluster_name       = module.aks_core.name
  create_aks_identity = true

  enable_workload_identity     = true
  create_federated_credentials = true
  create_role_assignments      = true
  aks_oidc_issuer_url          = module.aks_core.oidc_issuer_url
  node_resource_group_id       = module.aks_core.node_resource_group_id

  workload_identities = {
    "cert-manager" = {
      namespace       = "cert-manager"
      service_account = "cert-manager"
      roles           = ["DNS Zone Contributor"]
    }
    "karpenter" = {
      namespace       = "karpenter"
      service_account = "karpenter"
      roles           = ["Virtual Machine Contributor", "Network Contributor"]
    }
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terragrunt"
  }
}
```

## Examples

### Disabled

```hcl
module "identities" {
  source = "../identities"

  create              = false
  resource_group_name = "placeholder"
  location            = "eastus"
  environment         = "dev"
}
```

### AKS identity only (no workload identities)

```hcl
module "identities" {
  source = "../identities"

  create              = true
  resource_group_name = module.resource_group.name
  location            = "eastus"
  environment         = "dev"
  cluster_name        = "aks-platform-dev-eus"
  create_aks_identity = true

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
| [azurerm_federated_identity_credential.workload_credentials](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/federated_identity_credential) | resource |
| [azurerm_role_assignment.aks_managed_identity_operator](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aks_network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aks_subnet_network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.workload_node_rg_roles](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.aks_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.workload_identities](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| environment | Environment name (used for resource naming, ex: dev, qa, prod, ops). | `string` | n/a | yes |
| location | Azure region where identities will be created. | `string` | n/a | yes |
| resource_group_name | Name of the resource group where identities will be created. | `string` | n/a | yes |
| aks_identity_name | Name for the AKS cluster identity. If not specified, will be derived from the cluster name. | `string` | `null` | no |
| aks_oidc_issuer_url | The OIDC issuer URL of the AKS cluster. Required for federated credentials. | `string` | `null` | no |
| cluster_name | Name of the AKS cluster these identities are associated with. | `string` | `null` | no |
| create | Whether to create resources in this module | `bool` | `true` | no |
| create_aks_identity | Whether to create an identity for the AKS cluster. | `bool` | `true` | no |
| create_federated_credentials | Whether to create federated credentials for workload identities. Set to false for first phase deployment. | `bool` | `false` | no |
| create_role_assignments | Whether to create role assignments for workload identities. Set to false for first phase deployment. | `bool` | `false` | no |
| enable_workload_identity | Whether to enable workload identity for the cluster. | `bool` | `false` | no |
| node_resource_group_id | The ID of the node resource group for the AKS cluster. Required for role assignments. | `string` | `null` | no |
| workload | Workload name for resources. | `string` | `""` | no |
| private_route_table_name | Name of the private route table to assign to the AKS identity. | `string` | `null` | no |
| region_abbv | Region abbreviation for naming purposes. | `string` | `""` | no |
| subnet_id | ID of the subnet to assign to the AKS identity. | `string` | `null` | no |
| tags | Tags to apply to all resources. | `map(string)` | `{}` | no |
| vnet_resource_group_name | Name of the resource group containing the VNet and route tables. | `string` | `null` | no |
| workload_identities | Map of workload identities to create, with their configurations. | <pre>map(object({<br/>    name            = optional(string)<br/>    namespace       = string<br/>    service_account = string<br/>    roles           = list(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| aks_identity_client_id | Client ID of the user-assigned managed identity for the AKS cluster. |
| aks_identity_id | ID of the user-assigned managed identity for the AKS cluster. |
| aks_identity_principal_id | Principal ID of the user-assigned managed identity for the AKS cluster. |
| cert_manager_identity | Details of the cert-manager identity if created. |
| create | Whether resources were created |
| federated_identity_credentials | Map of all federated identity credentials created by the module. |
| karpenter_identity | Details of the Karpenter identity if created. |
| workload_identities | Map of all workload identities created by the module. |
<!-- END_TF_DOCS -->

## Dependencies

- [resource_group](../resource_group) -- resource group where identities are created
- [aks_core](../aks_core) -- provides OIDC issuer URL and node resource group for federated credentials and role assignments

## Notes

- `create_federated_credentials` and `create_role_assignments` default to `false` to support phased deployments where the AKS cluster must exist before federated credentials can be created.
- Workload identities are defined as a map; each entry creates a managed identity, a federated credential, and role assignments.
