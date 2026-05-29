# Managed Grafana

Creates an Azure Managed Grafana instance with a system-assigned identity, Microsoft Entra (Azure AD) integration, and optional Azure Monitor (Prometheus) workspace connectivity. The module supports configurable Grafana major version, zone redundancy, API key authentication, and Grafana Admin role assignments for both Entra groups and individual users.

## Usage

```hcl
module "managed_grafana" {
  source = "../../modules/azure/managed_grafana"

  name                    = "graf-platform-dev-eus"
  resource_group_name     = "rg-platform-dev-eus"
  location                = "eastus"
  prometheus_workspace_id = "/subscriptions/.../accounts/amw-platform-dev-eus-prometheus"

  admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]

  tags = {
    Environment = "dev"
    ManagedBy   = "Terraform"
  }
}
```

## Examples

### Disabled Module

```hcl
module "managed_grafana" {
  source = "../../modules/azure/managed_grafana"
  create = false
}
```

### Grafana 11 with User Admins

```hcl
module "managed_grafana" {
  source = "../../modules/azure/managed_grafana"

  name                    = "graf-platform-prod-eus"
  resource_group_name     = "rg-platform-prod-eus"
  location                = "eastus"
  grafana_major_version   = "11"
  zone_redundancy_enabled = true
  prometheus_workspace_id = "/subscriptions/.../accounts/amw-platform-prod-eus-prometheus"

  admin_group_object_ids = ["00000000-0000-0000-0000-000000000000"]
  admin_user_object_ids  = ["11111111-1111-1111-1111-111111111111"]
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
| [azurerm_dashboard_grafana.grafana](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/dashboard_grafana) | resource |
| [azurerm_role_assignment.grafana_admin_groups](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_role_assignment.grafana_admin_users](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_location"></a> [location](#input\_location) | The Azure region where the Grafana instance will be created | `string` | n/a | yes |
| <a name="input_resource_group_name"></a> [resource\_group\_name](#input\_resource\_group\_name) | The name of the resource group where the Grafana instance will be created | `string` | n/a | yes |
| <a name="input_admin_group_object_ids"></a> [admin\_group\_object\_ids](#input\_admin\_group\_object\_ids) | List of Microsoft Entra group Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| <a name="input_admin_user_object_ids"></a> [admin\_user\_object\_ids](#input\_admin\_user\_object\_ids) | List of Microsoft Entra user Object IDs that will have the Grafana Admin role | `list(string)` | `[]` | no |
| <a name="input_api_key_enabled"></a> [api\_key\_enabled](#input\_api\_key\_enabled) | Whether to enable API key authentication for the Grafana instance | `bool` | `true` | no |
| <a name="input_auto_generated_domain_name_label_scope"></a> [auto\_generated\_domain\_name\_label\_scope](#input\_auto\_generated\_domain\_name\_label\_scope) | The scope for the auto-generated domain name label | `string` | `"TenantReuse"` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_deterministic_outbound_ip_enabled"></a> [deterministic\_outbound\_ip\_enabled](#input\_deterministic\_outbound\_ip\_enabled) | Whether to enable deterministic outbound IPs for the Grafana instance | `bool` | `false` | no |
| <a name="input_environment"></a> [environment](#input\_environment) | Environment name for resource naming (dev, test, staging, prod, ops) | `string` | `"dev"` | no |
| <a name="input_grafana_major_version"></a> [grafana\_major\_version](#input\_grafana\_major\_version) | The major version of Grafana to use | `string` | `"10"` | no |
| <a name="input_name"></a> [name](#input\_name) | The name of the Azure Managed Grafana instance. If null, a name should be provided by Terragrunt using the naming module. | `string` | `null` | no |
| <a name="input_prometheus_workspace_id"></a> [prometheus\_workspace\_id](#input\_prometheus\_workspace\_id) | The resource ID of the Azure Monitor workspace to integrate with Grafana | `string` | `null` | no |
| <a name="input_public_network_access_enabled"></a> [public\_network\_access\_enabled](#input\_public\_network\_access\_enabled) | Whether to enable public network access for the Grafana instance | `bool` | `true` | no |
| <a name="input_region_abbv"></a> [region\_abbv](#input\_region\_abbv) | Abbreviation for Azure region (used in resource naming) | `string` | `"eus"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | A mapping of tags to assign to the resource | `map(string)` | `{}` | no |
| <a name="input_workload"></a> [workload](#input\_workload) | Workload identifier for resource names | `string` | `"platform"` | no |
| <a name="input_zone_redundancy_enabled"></a> [zone\_redundancy\_enabled](#input\_zone\_redundancy\_enabled) | Whether to enable zone redundancy for the Grafana instance | `bool` | `true` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_endpoint"></a> [endpoint](#output\_endpoint) | The endpoint URL of the Azure Managed Grafana instance |
| <a name="output_grafana_version"></a> [grafana\_version](#output\_grafana\_version) | The version of Grafana being used |
| <a name="output_id"></a> [id](#output\_id) | The ID of the Azure Managed Grafana instance |
| <a name="output_identity"></a> [identity](#output\_identity) | The identity of the Azure Managed Grafana instance |
| <a name="output_name"></a> [name](#output\_name) | The name of the Azure Managed Grafana instance |
| <a name="output_resource_group_name"></a> [resource\_group\_name](#output\_resource\_group\_name) | The name of the resource group where the Grafana instance is deployed |
<!-- END_TF_DOCS -->

## Notes

- The Grafana instance uses a system-assigned managed identity. This identity needs `Monitoring Reader` role on the Azure Monitor workspace to query Prometheus metrics -- that role assignment must be created separately.
- Prometheus integration is configured by setting `prometheus_workspace_id`. If null, no Azure Monitor workspace integration is created.
- API key authentication is enabled by default (`api_key_enabled = true`). This allows programmatic access to the Grafana API.
- Zone redundancy is enabled by default. Disable it for dev/test environments to reduce costs.
