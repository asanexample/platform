# Azure Client Config Module

Data source that exposes the current Azure client configuration (tenant ID, subscription ID, object ID, client ID).

## Usage

```hcl
module "client_config" {
  source = "../client_config"
}

# Use in role assignments or access policies
resource "azurerm_role_assignment" "deployer" {
  scope                = module.resource_group.id
  role_definition_name = "Contributor"
  principal_id         = module.client_config.object_id
}
```

## Examples

### Key Vault access policy for the current identity

```hcl
module "client_config" {
  source = "../client_config"
}

resource "azurerm_key_vault_access_policy" "deployer" {
  key_vault_id = module.key_vault.id
  tenant_id    = module.client_config.tenant_id
  object_id    = module.client_config.object_id

  secret_permissions = ["Get", "List", "Set", "Delete"]
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |

## Outputs

| Name | Description |
| ---- | ----------- |
| client_id | The client ID (application ID) of the current Azure client |
| object_id | The object ID of the current Azure client (user or service principal) |
| subscription_id | The subscription ID of the current Azure client |
| tenant_id | The tenant ID of the current Azure client |
<!-- END_TF_DOCS -->

## Dependencies

None -- this is a data-only module.

## Notes

- This module has no `create` variable and no inputs; it is a pure data source wrapper.
- The returned identity depends on how Terraform authenticates (user vs. service principal).
- Creates zero Azure resources.
