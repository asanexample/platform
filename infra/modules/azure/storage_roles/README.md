# Storage Roles

Creates Azure RBAC role assignments on a storage account for Entra ID (Azure AD) authentication. This module is designed for transitioning from shared access key authentication to identity-based access. Each role assignment specifies a principal, a role (by name or ID), and an optional scope override. When scope is not specified, assignments default to the storage account level.

## Usage

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"

  storage_account_id = "/subscriptions/.../storageAccounts/stplatdeveus001"

  role_assignments = [
    {
      principal_id         = "00000000-0000-0000-0000-000000000000"
      role_definition_name = "Storage Blob Data Contributor"
      description          = "App identity for blob read/write"
    },
    {
      principal_id         = "11111111-1111-1111-1111-111111111111"
      role_definition_name = "Storage Blob Data Reader"
      description          = "Monitoring identity for log access"
    }
  ]
}
```

## Examples

### Disabled Module

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"
  create = false
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
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_storage_account_id"></a> [storage\_account\_id](#input\_storage\_account\_id) | ID of the storage account to assign roles for | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | List of role assignments to create for Entra ID authentication. Should contain principal\_id, role\_definition\_name or role\_definition\_id, and scope (optional). | <pre>list(object({<br/>    principal_id         = string<br/>    role_definition_name = optional(string, null)<br/>    role_definition_id   = optional(string, null)<br/>    description          = optional(string, null)<br/>    scope                = optional(string, null) # Defaults to storage account resource ID<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_role_assignment_ids"></a> [role\_assignment\_ids](#output\_role\_assignment\_ids) | List of role assignment IDs created for Entra ID authentication |
<!-- END_TF_DOCS -->

## Notes

- Either `role_definition_name` or `role_definition_id` must be provided for each assignment, but not both.
- When `scope` is null (default), the role assignment is scoped to the `storage_account_id`. Override `scope` for container-level or resource-group-level assignments.
- This module uses `count` rather than `for_each`, so reordering the `role_assignments` list will cause recreation of assignments. For stable identity, use the `storage_container` module's built-in role assignment support instead.
