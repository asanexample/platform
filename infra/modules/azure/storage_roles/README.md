# Azure Storage Roles Module

Assigns RBAC roles on a storage account to enable Entra ID authentication for users, groups, and service principals.

## Usage

```hcl
module "storage_roles" {
  source = "../storage_roles"

  create = true

  storage_account_id = module.storage_account.id

  role_assignments = [
    {
      principal_id         = data.azuread_group.developers.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Developer team blob read/write access"
    },
    {
      principal_id         = data.azuread_service_principal.ci_pipeline.id
      role_definition_name = "Storage Blob Data Reader"
      description          = "CI pipeline read access"
    }
  ]
}
```

## Examples

### Disabled

```hcl
module "storage_roles" {
  source = "../storage_roles"
  create = false
}
```

### Container-scoped role

```hcl
module "storage_roles" {
  source = "../storage_roles"

  create = true

  storage_account_id = module.storage_account.id

  role_assignments = [
    {
      principal_id         = data.azuread_service_principal.app.id
      role_definition_name = "Storage Blob Data Owner"
      description          = "App full access to exports container"
      scope                = "${module.storage_account.id}/blobServices/default/containers/data-exports"
    }
  ]
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_role_assignment.this](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| storage_account_id | ID of the storage account to assign roles for | `string` | n/a | yes |
| create | Whether to create resources in this module | `bool` | `true` | no |
| role_assignments | List of role assignments to create for Entra ID authentication. Should contain principal_id, role_definition_name or role_definition_id, and scope (optional). | <pre>list(object({<br/>    principal_id         = string<br/>    role_definition_name = optional(string, null)<br/>    role_definition_id   = optional(string, null)<br/>    description          = optional(string, null)<br/>    scope                = optional(string, null) # Defaults to storage account resource ID<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| create | Whether resources were created |
| role_assignment_ids | List of role assignment IDs created for Entra ID authentication |
<!-- END_TF_DOCS -->

## Dependencies

- [storage_account](../storage_account) — Provides the storage account ID
- [identities](../identities) — Provides principal IDs for role assignment targets

## Notes

- Either `role_definition_name` or `role_definition_id` must be provided per assignment.
- Role assignments may take a few minutes to propagate in Azure.
