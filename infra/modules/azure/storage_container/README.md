# Storage Container

Creates one or more blob containers within an existing Azure Storage Account, with optional Entra ID (Azure AD) role assignments per container. This module decouples container lifecycle management from storage account creation, allowing separate teams or deployment phases to manage containers independently. Each container supports configurable access type (private, blob, container) and custom metadata.

## Usage

```hcl
module "storage_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = "/subscriptions/.../storageAccounts/stplatdeveus001"

  containers = {
    "tfstate" = {
      name                  = "tfstate"
      container_access_type = "private"
    }
    "logs" = {
      name     = "application-logs"
      metadata = { retention = "90days" }
    }
  }
}
```

## Examples

### Disabled Module

```hcl
module "storage_containers" {
  source = "../../modules/azure/storage_container"
  create = false
}
```

### With Role Assignments

```hcl
module "storage_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = "/subscriptions/.../storageAccounts/stplatdeveus001"

  containers = {
    "uploads" = {
      name                  = "user-uploads"
      container_access_type = "private"
    }
  }

  role_assignments = [
    {
      container_key        = "uploads"
      principal_id         = "00000000-0000-0000-0000-000000000000"
      role_definition_name = "Storage Blob Data Contributor"
      description          = "App service identity write access"
    }
  ]
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
| [azurerm_role_assignment.container_role_assignments](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/role_assignment) | resource |
| [azurerm_storage_container.containers](https://registry.terraform.io/providers/hashicorp/azurerm/latest/docs/resources/storage_container) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_containers"></a> [containers](#input\_containers) | Map of containers to create in the storage account | <pre>map(object({<br/>    # Name of the container - must follow Azure naming rules<br/>    name = string<br/>    # Access type: "private" (default), "blob" (anonymous blob read), or "container" (anonymous container read)<br/>    container_access_type = optional(string, "private")<br/>    # Optional metadata as key-value pairs to add to the container<br/>    metadata = optional(map(string), {})<br/>  }))</pre> | n/a | yes |
| <a name="input_storage_account_id"></a> [storage\_account\_id](#input\_storage\_account\_id) | ID of the Azure Storage Account where containers will be created | `string` | n/a | yes |
| <a name="input_create"></a> [create](#input\_create) | Whether to create resources in this module | `bool` | `true` | no |
| <a name="input_role_assignments"></a> [role\_assignments](#input\_role\_assignments) | List of role assignments to create for containers | <pre>list(object({<br/>    # Container key from var.containers to assign the role to<br/>    container_key = string<br/>    # Principal ID to give the role to (user, group, service principal, etc.)<br/>    principal_id = string<br/>    # The name of the role to assign (e.g., "Storage Blob Data Contributor")<br/>    role_definition_name = string<br/>    # Optional description for the role assignment<br/>    description = optional(string, null)<br/>    # Optional condition for the role assignment<br/>    condition = optional(string, null)<br/>    # Optional condition version for the role assignment<br/>    condition_version = optional(string, null)<br/>    # Optional principal type (ServicePrincipal, User, Group)<br/>    principal_type = optional(string, null)<br/>    # Optional skip service principal AAD check<br/>    skip_service_principal_aad_check = optional(bool, false)<br/>  }))</pre> | `[]` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_container_ids"></a> [container\_ids](#output\_container\_ids) | Map of container names to their resource IDs |
| <a name="output_container_names"></a> [container\_names](#output\_container\_names) | List of created container names |
| <a name="output_container_resource_manager_ids"></a> [container\_resource\_manager\_ids](#output\_container\_resource\_manager\_ids) | Map of container names to their resource manager IDs for use with role assignments |
| <a name="output_containers"></a> [containers](#output\_containers) | Map of created containers with their properties |
| <a name="output_create"></a> [create](#output\_create) | Whether resources were created |
| <a name="output_role_assignments"></a> [role\_assignments](#output\_role\_assignments) | Map of role assignments created for containers |
<!-- END_TF_DOCS -->

## Notes

- Container names must be 3-63 characters, lowercase alphanumeric and dashes, starting and ending with a letter or number.
- Access type `private` (default) disables anonymous access. Use `blob` for anonymous blob read or `container` for anonymous listing -- avoid these in production.
- Role assignments are scoped to individual containers using the `resource_manager_id`, enabling fine-grained Entra ID access control.
- Each `role_assignments` entry must reference a valid `container_key` from the `containers` map. This is validated at plan time.
