# AKS Identity

Creates user-assigned managed identities for AKS clusters and optional workload identities for services like cert-manager and Karpenter. The module provisions the primary AKS cluster identity with Network Contributor and Managed Identity Operator role assignments, and can create additional workload identities when `create_workload_identities` is enabled. Federated credentials are not created here because they require the OIDC issuer URL from an already-running cluster -- use a two-phase deployment approach or the `identities` module for that.

## Usage

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  cluster_name        = "aks-platform-dev-eus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"

  subnet_id                = "/subscriptions/.../subnets/snet-kubernetes"
  private_route_table_name = "rt-platform-dev-eus"
  vnet_resource_group_name = "rg-platform-dev-eus"

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"
  create = false
}
```

### With Workload Identities

```hcl
module "aks_identity" {
  source = "../../modules/azure/aks_identity"

  resource_group_name = "rg-platform-dev-eus"
  location            = "eastus"
  cluster_name        = "aks-platform-dev-eus"
  workload            = "platform"
  environment         = "dev"
  region_abbv         = "eus"

  create_workload_identities = true
  workload_identity_enabled  = true
  oidc_issuer_enabled        = true

  tags = {
    Environment = "dev"
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

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_role_assignment.aks_network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.aks_subnet_network_contributor](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.kubelet_managed_identity_operator](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_user_assigned_identity.aks_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.cert_manager_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_user_assigned_identity.karpenter_identity](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/user_assigned_identity) | resource |
| [azurerm_route_table.private](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/route_table) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_cluster_name"></a> [cluster\_name](#input\_cluster\_name) | The name of the AKS cluster the identities are for | `string` | n/a | yes |
| <a name="input_location"></a> [location](#input\_location) | The Azure location where the identities will be deployed | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The resource group name where the identities will be created | `string` | n/a | yes |
| <a name="input_aks_identity_name"></a> [aks\_identity\_name](#input\_aks\_identity\_name) | The name of the user-assigned managed identity for AKS | `string` | `null` | no |
| <a name="input_cert_manager_federated_credential_name"></a> [cert\_manager\_federated\_credential\_name](#input\_cert\_manager\_federated\_credential\_name) | The name of the cert-manager federated credential. If not provided, a name will be generated. | `string` | `null` | no |
| <a name="input_cert_manager_identity_name"></a> [cert\_manager\_identity\_name](#input\_cert\_manager\_identity\_name) | The name of the cert-manager identity. If not provided, a name will be generated. | `string` | `null` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_create_workload_identities"></a> [create\_workload\_identities](#input\_create\_workload\_identities) | Whether to create workload identities for common services like cert-manager and karpenter | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | The environment (e.g. dev, test, prod) | `string` | `"dev"` | no |
| <a name="input_karpenter_federated_credential_name"></a> [karpenter\_federated\_credential\_name](#input\_karpenter\_federated\_credential\_name) | The name of the karpenter federated credential. If not provided, a name will be generated. | `string` | `null` | no |
| <a name="input_karpenter_identity_name"></a> [karpenter\_identity\_name](#input\_karpenter\_identity\_name) | The name of the karpenter identity. If not provided, a name will be generated. | `string` | `null` | no |
| <a name="input_node_resource_group_id"></a> [node\_resource\_group\_id](#input\_node\_resource\_group\_id) | The ID of the node resource group created by AKS | `string` | `null` | no |
| <a name="input_oidc_issuer_enabled"></a> [oidc\_issuer\_enabled](#input\_oidc\_issuer\_enabled) | Whether OIDC issuer is enabled on the AKS cluster | `bool` | `false` | no |
| <a name="input_oidc_issuer_url"></a> [oidc\_issuer\_url](#input\_oidc\_issuer\_url) | The OIDC issuer URL of the AKS cluster | `string` | `null` | no |
| <a name="input_private_route_table_name"></a> [private\_route\_table\_name](#input\_private\_route\_table\_name) | The name of the private route table used by the AKS cluster | `string` | `null` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | The abbreviated region name | `string` | `"weu"` | no |
| <a name="input_subnet_id"></a> [subnet\_id](#input\_subnet\_id) | The ID of the subnet where the AKS cluster is deployed | `string` | `null` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_vnet_resource_group_name"></a> [vnet\_resource\_group\_name](#input\_vnet\_resource\_group\_name) | The resource group name containing the VNet and route table | `string` | `null` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | The workload identifier to use for all resources | `string` | `"platform"` | no |
| <a name="input_workload_identity_enabled"></a> [workload\_identity\_enabled](#input\_workload\_identity\_enabled) | Whether workload identity is enabled on the AKS cluster | `bool` | `false` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_aks_identity_client_id"></a> [aks\_identity\_client\_id](#output\_aks\_identity\_client\_id) | The client ID of the AKS cluster identity |
| <a name="output_aks_identity_id"></a> [aks\_identity\_id](#output\_aks\_identity\_id) | The ID of the AKS cluster identity |
| <a name="output_aks_identity_principal_id"></a> [aks\_identity\_principal\_id](#output\_aks\_identity\_principal\_id) | The principal ID of the AKS cluster identity |
| <a name="output_cert_manager_identity_client_id"></a> [cert\_manager\_identity\_client\_id](#output\_cert\_manager\_identity\_client\_id) | The client ID of the cert-manager identity |
| <a name="output_cert_manager_identity_id"></a> [cert\_manager\_identity\_id](#output\_cert\_manager\_identity\_id) | The ID of the cert-manager identity |
| <a name="output_cert_manager_identity_principal_id"></a> [cert\_manager\_identity\_principal\_id](#output\_cert\_manager\_identity\_principal\_id) | The principal ID of the cert-manager identity |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_karpenter_identity_client_id"></a> [karpenter\_identity\_client\_id](#output\_karpenter\_identity\_client\_id) | The client ID of the karpenter identity |
| <a name="output_karpenter_identity_id"></a> [karpenter\_identity\_id](#output\_karpenter\_identity\_id) | The ID of the karpenter identity |
| <a name="output_karpenter_identity_principal_id"></a> [karpenter\_identity\_principal\_id](#output\_karpenter\_identity\_principal\_id) | The principal ID of the karpenter identity |
<!-- END_TF_DOCS -->

## Notes

- The AKS identity is granted Network Contributor on the route table and subnet, plus Managed Identity Operator on itself -- all required for cluster provisioning with user-assigned identities.
- Workload identities for cert-manager and Karpenter are only created when all three flags are true: `create_workload_identities`, `workload_identity_enabled`, and `oidc_issuer_enabled`.
- Federated credentials and role assignments for workload identities require the AKS cluster to exist first. Use the `identities` module for full lifecycle management including federated credentials.
