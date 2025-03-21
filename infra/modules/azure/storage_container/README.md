# Azure Storage Container Module

This Terraform module manages Azure Storage Containers for existing Storage Accounts. It provides a simple, flexible way to create and manage multiple containers with granular control over access types and metadata.

## Features

- **Independent Container Management**: Manage containers separately from storage accounts
- **Bulk Container Creation**: Create multiple containers with a single module call
- **Flexible Access Control**: Configure access type per container (private, blob, or container)
- **Metadata Support**: Add optional metadata to containers for improved organization
- **Name Validation**: Enforces Azure Storage container naming requirements
- **Entra ID (Azure AD) Authentication**: Configure container-level role assignments with RBAC for secure access

## Usage

### Basic Usage

```hcl
module "blob_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = azurerm_storage_account.example.id

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
}
```

### With Metadata

```hcl
module "blob_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = azurerm_storage_account.example.id

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

### With Entra ID (Azure AD) Role Assignments

```hcl
module "blob_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = azurerm_storage_account.example.id

  containers = {
    "data" = {
      name                  = "data"
      container_access_type = "private"
    },
    "logs" = {
      name                  = "logs"
      container_access_type = "private"
    }
  }

  role_assignments = [
    {
      container_key        = "data"
      principal_id         = data.azurerm_client_config.current.object_id
      role_definition_name = "Storage Blob Data Contributor"
      description          = "Allows current user to read and write data in the container"
    },
    {
      container_key        = "logs"
      principal_id         = azuread_service_principal.example.object_id
      role_definition_name = "Storage Blob Data Reader"
      principal_type       = "ServicePrincipal"
      description          = "Allows monitoring service to read logs"
    }
  ]
}
```

### Using Outputs

```hcl
module "blob_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_id = azurerm_storage_account.example.id

  containers = {
    "images" = {
      name                  = "images"
      container_access_type = "blob"
    }
  }
}

# Access container properties in other resources
resource "azurerm_role_assignment" "container_contributor" {
  scope                = module.blob_containers.container_resource_manager_ids["images"]
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = "00000000-0000-0000-0000-000000000000" # Example user/service principal ID
}
```

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

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| storage_account_id | ID of the Azure Storage Account where containers will be created | `string` | n/a | yes |
| containers | Map of container configurations to create | `map(object)` | n/a | yes |
| role_assignments | List of role assignments to create for containers | `list(object)` | `[]` | no |

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

## Notes

### Container Naming Rules

Azure Storage container names must follow these rules:
- Must be between 3 and 63 characters
- Can contain only lowercase letters, numbers, and hyphens
- Cannot start or end with a hyphen
- Cannot contain consecutive hyphens

### Container Access Types

- **private**: No anonymous access (default)
- **blob**: Anonymous read access for blobs only
- **container**: Anonymous read access for containers and blobs (least secure)

### Security Best Practices

- Use `private` access type whenever possible
- Prefer Entra ID authentication with appropriate RBAC roles
- For public content, prefer `blob` access over `container` access
- Consider using Azure CDN for public content rather than direct blob access
- Implement role-based access control (RBAC) for more granular permissions

### Metadata Limitations

- Metadata keys must be valid HTTP header names and are case-insensitive
- Total size of all metadata cannot exceed 8KB
- Avoid special characters in keys and values

## Related Modules

- [storage_account](../storage_account): Creates Azure Storage Accounts
- [storage_roles](../storage_roles): Manages role assignments for storage accounts

## License

This module is licensed under the MIT License - see the LICENSE file for details. 