# Azure Storage Roles Module

This Terraform module creates role assignments for Azure Storage accounts to enable Entra ID (Azure AD) authentication.

## Purpose

This module is designed to:

- Provide a dedicated way to manage access control for storage accounts
- Support the transition from access keys to Entra ID authentication
- Enable separation of infrastructure provisioning from access management
- Support flexible role assignments at different scopes (account, container, etc.)

## Features

- Creates role assignments for users, groups, or service principals
- Supports multiple built-in Azure roles for storage access
- Allows custom scope definitions for granular permissions
- Prevents accidental deletion of role assignments with lifecycle rules

## Usage

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"

  # Storage account to assign roles for
  storage_account_id = "/subscriptions/.../resourceGroups/my-rg/providers/Microsoft.Storage/storageAccounts/mystorageacct"
  
  # Role assignments
  role_assignments = [
    {
      # User assignment
      principal_id         = "00000000-0000-0000-0000-000000000000" # Object ID of user
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant Blob Data Contributor access to developer"
    },
    {
      # Group assignment
      principal_id         = "11111111-1111-1111-1111-111111111111" # Object ID of group
      role_definition_name = "Storage Blob Data Reader"
      description          = "Grant read access to data science team"
    },
    {
      # Container-level assignment
      principal_id         = "22222222-2222-2222-2222-222222222222" # Object ID of service principal
      role_definition_name = "Storage Blob Data Owner"
      description          = "Grant owner access to specific container"
      scope                = "${var.storage_account_id}/blobServices/default/containers/my-container"
    }
  ]
}
```

## Common Storage Roles

| Role Name | Description | Use Case |
|-----------|-------------|----------|
| Storage Blob Data Owner | Full access to Storage blob containers and data | For administrators |
| Storage Blob Data Contributor | Read, write, and delete access to Storage blob containers and data | For applications that need read/write access |
| Storage Blob Data Reader | Read access to Storage blob containers and data | For applications that only need read access |
| Storage Queue Data Contributor | Read, write, and delete access to Azure Storage queues and messages | For queue processing applications |
| Storage Queue Data Reader | Read and process access to Azure Storage queues and messages | For queue monitoring applications |
| Storage Table Data Contributor | Read, write, and delete access to Azure Storage tables | For applications using Table storage |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| storage_account_id | ID of the storage account to assign roles for | `string` | n/a | yes |
| role_assignments | List of role assignments to create | `list(object)` | `[]` | no |

The `role_assignments` object supports the following attributes:

```
{
  principal_id: string         # Object ID of the principal (user, group, or service principal)
  role_definition_name: string # Name of the built-in role (e.g., "Storage Blob Data Contributor")
  role_definition_id: string   # ID of the role definition (alternative to role_definition_name)
  description: string          # Optional description for the role assignment
  scope: string                # Optional custom scope for the role assignment
}
```

## Outputs

| Name | Description |
|------|-------------|
| role_assignment_ids | List of IDs for the created role assignments | 