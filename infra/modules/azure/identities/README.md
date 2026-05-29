# Identities

Creates and manages all managed identities for an AKS cluster: the cluster control plane identity, workload identities for Kubernetes services, federated identity credentials for OIDC token exchange, and RBAC role assignments. This is the comprehensive identity module that supports the full lifecycle including federated credentials (unlike `aks_identity`, which handles only pre-cluster identity creation). It uses the `naming` module internally for consistent resource names.

## Usage

```hcl
module "identities" {
  source = "../../modules/azure/identities"

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"
  cluster_name        = "aks-platform-dev-eus"

  create_aks_identity      = true
  subnet_id                = "/subscriptions/.../subnets/snet-kubernetes"
  private_route_table_name = "rt-platform-dev-eus"
  vnet_resource_group_name = "rg-platform-dev-eus"

  enable_workload_identity     = true
  create_federated_credentials = true
  create_role_assignments      = true
  aks_oidc_issuer_url          = "https://oidcissuer.example.com/..."
  node_resource_group_id       = "/subscriptions/.../resourceGroups/MC_rg-platform-dev-eus_aks-platform-dev-eus_eastus"

  workload_identities = {
    "cert-manager" = {
      namespace       = "cert-manager"
      service_account = "cert-manager"
      roles           = ["DNS Zone Contributor"]
    }
    "karpenter" = {
      namespace       = "kube-system"
      service_account = "karpenter"
      roles           = ["Virtual Machine Contributor", "Network Contributor"]
    }
  }

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "identities" {
  source = "../../modules/azure/identities"
  create = false
}
```

### Phase 1: Pre-Cluster (Identity Only)

```hcl
module "identities" {
  source = "../../modules/azure/identities"

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"
  cluster_name        = "aks-platform-dev-eus"

  create_aks_identity          = true
  enable_workload_identity     = true
  create_federated_credentials = false
  create_role_assignments      = false

  workload_identities = {
    "cert-manager" = {
      namespace       = "cert-manager"
      service_account = "cert-manager"
      roles           = ["DNS Zone Contributor"]
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Requirements

No requirements.

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_azurerm"></a> [azurerm](#provider\_azurerm) | n/a |

## Modules

| Name | Source | Version |
| ---- | ------ | ------- |
| <a name="module_naming"></a> [naming](#module\_naming) | ../naming | n/a |

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
| [azurerm_route_table.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/route_table) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name (used for resource naming, ex: dev, qa, prod, ops). | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | Azure region where identities will be created. | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | Name of the resource group where identities will be created. | `string` | n/a | yes |
| <a name="input_aks_identity_name"></a> [aks\_identity\_name](#input\_aks\_identity\_name) | Name for the AKS cluster identity. If not specified, will be derived from the cluster name. | `string` | `null` | no |
| <a name="input_aks_oidc_issuer_url"></a> [aks\_oidc\_issuer\_url](#input\_aks\_oidc\_issuer\_url) | The OIDC issuer URL of the AKS cluster. Required for federated credentials. | `string` | `null` | no |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | Name of the AKS cluster these identities are associated with. | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_create_aks_identity"></a> [create\_aks\_identity](#input\_create\_aks\_identity) | Whether to create an identity for the AKS cluster. | `bool` | `true` | no |
| <a name="input_create_federated_credentials"></a> [create\_federated\_credentials](#input\_create\_federated\_credentials) | Whether to create federated credentials for workload identities. Set to false for first phase deployment. | `bool` | `false` | no |
| <a name="input_create_role_assignments"></a> [create\_role\_assignments](#input\_create\_role\_assignments) | Whether to create role assignments for workload identities. Set to false for first phase deployment. | `bool` | `false` | no |
| <a name="input_enable_workload_identity"></a> [enable\_workload\_identity](#input\_enable\_workload\_identity) | Whether to enable workload identity for the cluster. | `bool` | `false` | no |
| <a name="input_node_resource_group_id"></a> [node\_resource\_group\_id](#input\_node\_resource\_group\_id) | The ID of the node resource group for the AKS cluster. Required for role assignments. | `string` | `null` | no |
| <a name="input_private_route_table_name"></a> [private\_route\_table\_name](#input\_private\_route\_table\_name) | Name of the private route table to assign to the AKS identity. | `string` | `null` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Region abbreviation for naming purposes. | `string` | `""` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | ID of the subnet to assign to the AKS identity. | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources. | `map(string)` | `{}` | no |
| <a name="input_vnet_resource_group_name"></a> [vnet\_resource\_group\_name](#input\_vnet\_resource\_group\_name) | Name of the resource group containing the VNet and route tables. | `string` | `null` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource naming. | `string` | `"platform"` | no |
| <a name="input_workload_identities"></a> [workload\_identities](#input\_workload\_identities) | Map of workload identities to create, with their configurations. | <pre>map(object({<br/>    name            = optional(string)<br/>    namespace       = string<br/>    service_account = string<br/>    roles           = list(string)<br/>  }))</pre> | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_aks_identity_client_id"></a> [aks\_identity\_client\_id](#output\_aks\_identity\_client\_id) | Client ID of the user-assigned managed identity for the AKS cluster. |
| <a name="output_aks_identity_id"></a> [aks\_identity\_id](#output\_aks\_identity\_id) | ID of the user-assigned managed identity for the AKS cluster. |
| <a name="output_aks_identity_principal_id"></a> [aks\_identity\_principal\_id](#output\_aks\_identity\_principal\_id) | Principal ID of the user-assigned managed identity for the AKS cluster. |
| <a name="output_cert_manager_identity"></a> [cert\_manager\_identity](#output\_cert\_manager\_identity) | Details of the cert-manager identity if created. |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_federated_identity_credentials"></a> [federated\_identity\_credentials](#output\_federated\_identity\_credentials) | Map of all federated identity credentials created by the module. |
| <a name="output_karpenter_identity"></a> [karpenter\_identity](#output\_karpenter\_identity) | Details of the Karpenter identity if created. |
| <a name="output_workload_identities"></a> [workload\_identities](#output\_workload\_identities) | Map of all workload identities created by the module. |
<!-- END_TF_DOCS -->

## Notes

- This module supports a two-phase deployment pattern: set `create_federated_credentials = false` and `create_role_assignments = false` before the AKS cluster exists, then enable them after the cluster provides its OIDC issuer URL and node resource group.
- Federated credentials bind Kubernetes service accounts to Azure identities using the `system:serviceaccount:{namespace}:{service_account}` subject format with the `api://AzureADTokenExchange` audience.
- Role assignments for workload identities are scoped to the AKS node resource group (`node_resource_group_id`).
- Convenience outputs `cert_manager_identity` and `karpenter_identity` are provided when those keys exist in the `workload_identities` map.
