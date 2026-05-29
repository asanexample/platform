# Client Config

Exposes the current Azure client configuration (tenant ID, subscription ID, client ID, and object ID) as outputs. This is a data-only module that creates no resources -- it wraps `azurerm_client_config` so other modules can reference the authenticated principal's details without duplicating data source declarations.

## Usage

```hcl
module "client_config" {
  source = "../../modules/azure/client_config"
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
| [azurerm_client_config.current](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/data-sources/client_config) | data source |

## Inputs

No inputs.

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_client_id"></a> [client\_id](#output\_client\_id) | The client ID (application ID) of the current Azure client |
| <a name="output_object_id"></a> [object\_id](#output\_object\_id) | The object ID of the current Azure client (user or service principal) |
| <a name="output_subscription_id"></a> [subscription\_id](#output\_subscription\_id) | The subscription ID of the current Azure client |
| <a name="output_tenant_id"></a> [tenant\_id](#output\_tenant\_id) | The tenant ID of the current Azure client |
<!-- END_TF_DOCS -->

## Notes

- This module has no input variables and creates no Azure resources. It only reads the current authentication context.
- Useful for dynamically setting `tenant_id` or `object_id` on Key Vault access policies, role assignments, or other identity-dependent resources.
