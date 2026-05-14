# Azure Storage Container Module

Creates blob containers within an existing storage account with optional per-container RBAC role assignments.

## Usage

```hcl
module "storage_containers" {
  source = "../storage_container"

  create = true

  storage_account_id = module.storage_account.id

  containers = {
    "tfstate" = {
      name                  = "tfstate"
      container_access_type = "private"
    }
    "backups" = {
      name                  = "backups"
      container_access_type = "private"
    }
  }

  role_assignments = [
    {
      container_key        = "tfstate"
      principal_id         = data.azuread_group.platform_team.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Platform team read/write access to tfstate"
    }
  ]
}
```

## Examples

### Disabled

```hcl
module "storage_containers" {
  source = "../storage_container"
  create = false
}
```

### Containers without role assignments

```hcl
module "storage_containers" {
  source = "../storage_container"

  create = true

  storage_account_id = module.storage_account.id

  containers = {
    "logs" = {
      name                  = "logs"
      container_access_type = "private"
    }
  }
}
```

<!-- BEGIN_TF_DOCS -->
## Resources

| Name | Type |
| ---- | ---- |
| [azurerm_role_assignment.container_role_assignments](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_container.containers](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| containers | Map of containers to create in the storage account | <pre>map(object({<br/>    # Name of the container - must follow Azure naming rules<br/>    name = string<br/>    # Access type: "private" (default), "blob" (anonymous blob read), or "container" (anonymous container read)<br/>    container_access_type = optional(string, "private")<br/>    # Optional metadata as key-value pairs to add to the container<br/>    metadata = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| storage_account_id | ID of the Azure Storage Account where containers will be created | `string` | n/a | yes |
| create | Whether to create resources in this module | `bool` | `true` | no |
| role_assignments | List of role assignments to create for containers | <pre>list(object({<br/>    # Container key from var.containers to assign the role to<br/>    container_key = string<br/>    # Principal ID to give the role to (user, group, service principal, etc.)<br/>    principal_id = string<br/>    # The name of the role to assign (e.g., "Storage Blob Data Contributor")<br/>    role_definition_name = string<br/>    # Optional description for the role assignment<br/>    description = optional(string, null)<br/>    # Optional condition for the role assignment<br/>    condition = optional(string, null)<br/>    # Optional condition version for the role assignment<br/>    condition_version = optional(string, null)<br/>    # Optional principal type (ServicePrincipal, User, Group)<br/>    principal_type = optional(string, null)<br/>    # Optional skip service principal AAD check<br/>    skip_service_principal_aad_check = optional(bool, false)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| container_ids | Map of container names to their resource IDs |
| container_names | List of created container names |
| container_resource_manager_ids | Map of container names to their resource manager IDs for use with role assignments |
| containers | Map of created containers with their properties |
| create | Whether resources were created |
| role_assignments | Map of role assignments created for containers |
<!-- END_TF_DOCS -->

## Dependencies

- [storage_account](../storage_account) — Provides the storage account ID

## Notes

- This module manages containers only, not the storage account itself.
- Container names must be 3-63 characters, lowercase alphanumeric and hyphens, cannot start or end with a hyphen.
