# Azure Storage Roles Module

## Overview

This module creates role assignments for Azure Storage accounts to enable Entra ID (Azure AD) authentication. It provides a dedicated way to manage access control for storage accounts, supporting the transition from access keys to modern identity-based authentication.

## Features

- Creates role assignments for users, groups, and service principals
- Supports multiple built-in Azure roles for storage access
- Enables granular permissions with flexible scope definitions
- Separates infrastructure provisioning from access management
- Prevents accidental deletion of role assignments with lifecycle rules
- Supports container-level or account-level permissions

## Usage

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"

  # Storage account to assign roles for
  storage_account_id = module.storage_account.id
  
  # Role assignments
  role_assignments = [
    {
      # User assignment
      principal_id         = data.azuread_user.developer.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant Blob Data Contributor access to developer"
    },
    {
      # Group assignment
      principal_id         = data.azuread_group.data_scientists.id
      role_definition_name = "Storage Blob Data Reader"
      description          = "Grant read access to data science team"
    },
    {
      # Container-level assignment
      principal_id         = data.azuread_service_principal.automation_app.id
      role_definition_name = "Storage Blob Data Owner"
      description          = "Grant owner access to specific container"
      scope                = "${module.storage_account.id}/blobServices/default/containers/data-exports"
    }
  ]
}
```

## Examples

### Basic Account-Level Access

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"

  storage_account_id = module.storage_account.id
  
  role_assignments = [
    {
      principal_id         = data.azuread_group.developers.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant write access to development team"
    },
    {
      principal_id         = data.azuread_group.operations.id
      role_definition_name = "Storage Blob Data Reader"
      description          = "Grant read access to operations team"
    }
  ]
}
```

### Container-Level Access Control

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"

  storage_account_id = module.storage_account.id
  
  role_assignments = [
    {
      principal_id         = data.azuread_service_principal.app_a.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant write access to app A container"
      scope                = "${module.storage_account.id}/blobServices/default/containers/app-a-data"
    },
    {
      principal_id         = data.azuread_service_principal.app_b.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Grant write access to app B container"
      scope                = "${module.storage_account.id}/blobServices/default/containers/app-b-data"
    },
    {
      principal_id         = data.azuread_group.auditors.id
      role_definition_name = "Storage Blob Data Reader"
      description          = "Grant read access to auditors for all containers"
    }
  ]
}
```

### Queue and Table Storage Access

```hcl
module "storage_roles" {
  source = "../../modules/azure/storage_roles"

  storage_account_id = module.storage_account.id
  
  role_assignments = [
    {
      principal_id         = data.azuread_service_principal.queue_processor.id
      role_definition_name = "Storage Queue Data Contributor"
      description          = "Grant queue processing access"
    },
    {
      principal_id         = data.azuread_service_principal.reporting_app.id
      role_definition_name = "Storage Table Data Reader"
      description          = "Grant table read access for reporting"
    }
  ]
}
```

## Requirements

| Name | Version |
|------|---------|
| terraform | >= 1.6.0 |
| azurerm | >= 4.0.0 |

## Providers

| Name | Version |
|------|---------|
| azurerm | >= 4.0.0 |

## Required Inputs

| Name | Description | Type |
|------|-------------|------|
| storage_account_id | ID of the storage account to assign roles for | `string` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| role_assignments | List of role assignments to create | `list(object)` | `[]` | no |

### Role Assignment Object Structure

The `role_assignments` object supports the following attributes:

```hcl
role_assignments = [
  {
    principal_id         = string  # Required: Object ID of the principal (user, group, or service principal)
    role_definition_name = string  # Optional: Name of the built-in role (e.g., "Storage Blob Data Contributor")
    role_definition_id   = string  # Optional: ID of the role definition (alternative to role_definition_name)
    description          = string  # Optional: Description for the role assignment
    scope                = string  # Optional: Custom scope for the role assignment (defaults to storage account ID)
    principal_type       = string  # Optional: Type of principal (User, Group, ServicePrincipal)
  }
]
```

**Note:** Either `role_definition_name` or `role_definition_id` must be specified.

## Outputs

| Name | Description |
|------|-------------|
| role_assignment_ids | List of IDs for the created role assignments |

## Module Resources

This module creates the following resources:
- Azure Role Assignments for Storage Account access

## Dependencies

This module depends on:
- Storage Account resource must exist before role assignments can be created

## Common Storage Roles

| Role Name | Description | Use Case |
|-----------|-------------|----------|
| Storage Blob Data Owner | Full access to Storage blob containers and data | For administrators |
| Storage Blob Data Contributor | Read, write, and delete access to Storage blob containers and data | For applications that need read/write access |
| Storage Blob Data Reader | Read access to Storage blob containers and data | For applications that only need read access |
| Storage Queue Data Contributor | Read, write, and delete access to Azure Storage queues and messages | For queue processing applications |
| Storage Queue Data Reader | Read and process access to Azure Storage queues and messages | For queue monitoring applications |
| Storage Table Data Contributor | Read, write, and delete access to Azure Storage tables | For applications using Table storage |
| Storage Table Data Reader | Read access to Azure Storage tables | For applications that only need to read table data |
| Storage Account Contributor | Manage storage accounts | For infrastructure management |

## Authentication Best Practices

This module supports the Azure recommended practice of using Entra ID (formerly Azure AD) authentication for storage access:

1. **Eliminate Access Keys** - Reduce security risks by avoiding shared access keys
2. **Use Principle of Least Privilege** - Assign the minimum necessary permissions
3. **Implement Just-in-Time Access** - Use time-limited role assignments for administrative access
4. **Separate Duties** - Divide access based on responsibilities and functions
5. **Monitor Access** - Regularly audit role assignments and access patterns

## Scope Definitions

Role assignments can be created at different scopes:

- **Account level**: `storage_account_id`
  - Default scope when no custom scope is specified
  - Grants access to the entire storage account

- **Container level**: `${storage_account_id}/blobServices/default/containers/{container-name}`
  - Grants access to a specific container only
  - Useful for multi-tenant scenarios or segregation of responsibilities

- **Queue level**: `${storage_account_id}/queueServices/default/queues/{queue-name}`
  - Grants access to a specific queue

- **Table level**: `${storage_account_id}/tableServices/default/tables/{table-name}`
  - Grants access to a specific table

## Notes

- Role assignments may take a few minutes to propagate in Azure
- Deleting and recreating role assignments with the same properties may cause conflicts
- Role assignments require appropriate management permissions for the deploying identity
- For production environments, consider using Terraform state locking to prevent concurrent modifications
- When migrating from access keys, ensure applications are updated to use Entra ID authentication

## License

This module is licensed under the MIT License. 