# Azure Storage Container Module

## Overview

This module manages Azure Storage Containers for existing Storage Accounts. It provides a flexible and secure way to create and manage multiple blob containers with granular access control, metadata support, and role-based access control.

## Features

- Creates and manages multiple Azure Storage containers in a single module call
- Configures container access types (private, blob, or container) for each container
- Supports container metadata for improved organization and tagging
- Enforces Azure Storage container naming requirements through validation
- Enables Entra ID (Azure AD) authentication with container-level RBAC
- Outputs container properties and resource IDs for downstream dependencies

## Usage

```hcl
module "blob_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = module.storage_account.id

  containers = {
    "data" = {
      name                  = "data"
      container_access_type = "private"
    },
    "public-assets" = {
      name                  = "public-assets"
      container_access_type = "blob"
    }
  }
  
  role_assignments = [
    {
      container_key        = "data"
      principal_id         = "00000000-0000-0000-0000-000000000000"
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Allows data team to read and write data"
    }
  ]
}
```

## Examples

### Basic Storage Containers

```hcl
module "basic_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = module.storage_account.id

  containers = {
    "logs" = {
      name                  = "logs"
      container_access_type = "private"
    },
    "backups" = {
      name                  = "backups"
      container_access_type = "private"
    }
  }
}
```

### Containers with Metadata

```hcl
module "metadata_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = module.storage_account.id

  containers = {
    "app-backups" = {
      name                  = "app-backups"
      container_access_type = "private"
      metadata = {
        application = "inventory-system"
        environment = "production"
        retention   = "3-years"
      }
    },
    "user-uploads" = {
      name                  = "user-uploads"
      container_access_type = "private"
      metadata = {
        application = "user-portal"
        data-classification = "confidential"
      }
    }
  }
}
```

### RBAC with Container-level Access Control

```hcl
module "rbac_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = module.storage_account.id

  containers = {
    "finance" = {
      name                  = "finance"
      container_access_type = "private"
    },
    "marketing" = {
      name                  = "marketing"
      container_access_type = "private"
    }
  }

  role_assignments = [
    {
      container_key        = "finance"
      principal_id         = data.azuread_group.finance_team.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Finance team can read and write financial data"
    },
    {
      container_key        = "marketing"
      principal_id         = data.azuread_group.marketing_team.id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Marketing team can read and write marketing assets"
    },
    {
      container_key        = "marketing"
      principal_id         = data.azuread_service_principal.cdn_service.id
      role_definition_name = "Storage Blob Data Reader"
      principal_type       = "ServicePrincipal"
      description          = "CDN service can read marketing assets"
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
| storage_account_id | ID of the Azure Storage Account where containers will be created | `string` |
| containers | Map of container configurations to create | `map(object)` |

## Optional Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| role_assignments | List of role assignments to create for containers | `list(object)` | `[]` | no |

### Container Configuration Object

The `containers` object accepts the following properties:

```hcl
containers = {
  "example" = {
    name                  = string           # Required: Container name (must be lowercase, alphanumeric or dash)
    container_access_type = string           # Optional: Access type ("private", "blob", "container")
    metadata              = map(string)      # Optional: Container metadata key-value pairs
  }
}
```

### Role Assignment Configuration Object

The `role_assignments` object accepts the following properties:

```hcl
role_assignments = [
  {
    container_key                    = string           # Required: Key of the container in the containers map
    principal_id                     = string           # Required: Azure AD principal ID to assign the role to
    role_definition_name             = string           # Required: Name of the built-in role to assign
    description                      = string           # Optional: Description for the role assignment
    condition                        = string           # Optional: Condition for the role assignment
    condition_version                = string           # Optional: Version of the condition
    principal_type                   = string           # Optional: Type of principal (ServicePrincipal, User, Group)
    skip_service_principal_aad_check = bool             # Optional: Skip the AAD check for service principals
  }
]
```

## Outputs

| Name | Description |
|------|-------------|
| container_ids | Map of container names to their resource IDs |
| container_resource_manager_ids | Map of container names to their resource manager IDs (for role assignments) |
| container_names | List of all created container names |
| containers | Map of container names to their properties |
| role_assignments | Map of role assignments created for containers |

## Module Resources

This module creates the following resources:
- Azure Storage Containers
- Azure Role Assignments (optional)

## Dependencies

This module depends on:
- [storage_account](../storage_account) - For the storage account ID

## Authentication Methods

### Entra ID (Azure AD) Authentication (Recommended)

Entra ID (formerly Azure AD) authentication is the recommended approach for accessing blob storage. This method uses Azure role-based access control (RBAC) with role assignments for specific principals (users, groups, service principals). 

Benefits:
- Fine-grained access control at the container level
- No shared secrets to manage
- Integration with Azure's identity management
- Supports conditional access policies

Use the `role_assignments` variable to define container-level permissions. Common storage roles include:

| Role Name | Description |
|-----------|-------------|
| Storage Blob Data Reader | Read-only access to blob container data and metadata |
| Storage Blob Data Contributor | Read, write, and delete access to blob container data and metadata |
| Storage Blob Data Owner | Full access including permissions management |

### Shared Access Signatures (SAS)

For scenarios requiring temporary access or when Entra ID is not suitable, you can generate SAS tokens separately after container creation.

## Container Access Types

The module supports the following container access types:

- **private**: No anonymous access (default)
- **blob**: Anonymous read access for blobs only
- **container**: Anonymous read access for containers and blobs (least secure)

## Security Best Practices

For production environments, consider implementing the following security measures:

1. **Use Private Access Type** - Use `private` access type for all containers unless public access is specifically required
2. **Implement RBAC** - Use role assignments with the principle of least privilege
3. **Use Conditional Access** - For sensitive data, consider using conditional access policies with Entra ID
4. **Limit Public Access** - If public access is needed, prefer `blob` access over `container` access
5. **Consider Azure CDN** - For public content, use Azure CDN rather than direct blob access
6. **Audit Container Access** - Regularly review container access settings and permissions

## Container Naming Rules

Azure Storage container names must follow these rules:
- Must be between 3 and 63 characters
- Can contain only lowercase letters, numbers, and hyphens
- Cannot start or end with a hyphen
- Cannot contain consecutive hyphens

## Metadata Limitations

When using container metadata, be aware of these limitations:
- Metadata keys must be valid HTTP header names and are case-insensitive
- Total size of all metadata cannot exceed 8KB
- Avoid special characters in keys and values

## Notes

- This module only manages containers and not the storage account itself
- For managing storage accounts, use the [storage_account](../storage_account) module
- Role assignments require the deploying identity to have sufficient permissions on the storage account
- Consider using storage lifecycle management policies for data retention requirements
- For containers with private data, ensure proper security controls are in place

## License

This module is licensed under the MIT License. 