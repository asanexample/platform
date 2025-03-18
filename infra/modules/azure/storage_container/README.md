# Azure Storage Container Module

This Terraform module manages Azure Storage Containers for existing Storage Accounts. It provides a simple, flexible way to create and manage multiple containers with granular control over access types and metadata.

## Features

- **Independent Container Management**: Manage containers separately from storage accounts
- **Bulk Container Creation**: Create multiple containers with a single module call
- **Flexible Access Control**: Configure access type per container (private, blob, or container)
- **Metadata Support**: Add optional metadata to containers for improved organization
- **Name Validation**: Enforces Azure Storage container naming requirements

## Usage

### Basic Usage

```hcl
module "blob_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_name = "myexistingstorageacct"
  resource_group_name  = "my-resources-rg"

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

  storage_account_name = "myexistingstorageacct"
  resource_group_name  = "my-resources-rg"

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

### Using Outputs

```hcl
module "blob_containers" {
  source = "../../modules/azure/storage_container"

  storage_account_name = "myexistingstorageacct"
  resource_group_name  = "my-resources-rg"

  containers = {
    "images" = {
      name                  = "images"
      container_access_type = "blob"
    }
  }
}

# Access container properties in other resources
resource "azurerm_role_assignment" "container_contributor" {
  scope                = module.blob_containers.container_ids["images"]
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = "00000000-0000-0000-0000-000000000000" # Example user/service principal ID
}
```

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|----------|
| storage_account_name | Name of the existing storage account | `string` | n/a | yes |
| resource_group_name | Name of the resource group containing the storage account | `string` | n/a | yes |
| containers | Map of container configurations to create | `map(object)` | n/a | yes |

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

## Outputs

| Name | Description |
|------|-------------|
| container_ids | Map of container names to their resource IDs |
| container_names | List of all created container names |
| containers | Map of container names to their properties |

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
- For public content, prefer `blob` access over `container` access
- Consider using Azure CDN for public content rather than direct blob access
- Implement role-based access control (RBAC) for more granular permissions

### Metadata Limitations

- Metadata keys must be valid HTTP header names and are case-insensitive
- Total size of all metadata cannot exceed 8KB
- Avoid special characters in keys and values

## Related Modules

- [storage_account](../storage_account): Creates Azure Storage Accounts

## License

This module is licensed under the MIT License - see the LICENSE file for details. 