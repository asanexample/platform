# Azure Client Config Module

## Overview

This module exposes the current Azure client configuration, which includes details about the current user or service principal. It is a utility module that helps retrieve information about the authenticating entity for use in other Terraform configurations, particularly for role assignments.

## Features

- Provides access to the current Azure client configuration
- Exposes client ID, tenant ID, subscription ID, and object ID
- Useful for automatically configuring role assignments based on the current identity
- Zero resources created - purely a data source wrapper

## Usage

```hcl
module "client_config" {
  source = "../../modules/azure/client_config"
}

# Use the client configuration in other resources
resource "azurerm_role_assignment" "example" {
  scope                = azurerm_resource_group.example.id
  role_definition_name = "Contributor"
  principal_id         = module.client_config.object_id
}
```

## Examples

### Basic Usage

```hcl
module "client_config" {
  source = "../../modules/azure/client_config"
}

output "current_user_object_id" {
  value = module.client_config.object_id
}
```

### Using for Role Assignment

```hcl
module "client_config" {
  source = "../../modules/azure/client_config"
}

module "resource_group" {
  source              = "../../modules/azure/resource_group"
  name                = "rg-example"
  location            = "eastus"
}

resource "azurerm_role_assignment" "current_user_owner" {
  scope                = module.resource_group.id
  role_definition_name = "Owner"
  principal_id         = module.client_config.object_id
}
```

### Managing Key Vault Access Policies

```hcl
module "client_config" {
  source = "../../modules/azure/client_config"
}

module "key_vault" {
  source              = "../../modules/azure/key_vault"
  name                = "kv-example"
  resource_group_name = module.resource_group.name
  location            = "eastus"
}

resource "azurerm_key_vault_access_policy" "terraform_identity" {
  key_vault_id = module.key_vault.id
  tenant_id    = module.client_config.tenant_id
  object_id    = module.client_config.object_id
  
  key_permissions = [
    "Get", "List", "Create", "Delete", "Update"
  ]
  
  secret_permissions = [
    "Get", "List", "Set", "Delete"
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

## Inputs

This module accepts no inputs.

## Outputs

| Name | Description |
|------|-------------|
| client_id | The client ID (application ID) of the current Azure client |
| tenant_id | The tenant ID of the current Azure client |
| subscription_id | The subscription ID of the current Azure client |
| object_id | The object ID of the current Azure client (user or service principal) |

## Module Resources

This module retrieves the following data:
- Azure client configuration data source

## Dependencies

This module has no dependencies on other modules.

## Notes

- This module is often used in conjunction with role assignment resources or modules
- The values returned depend on the authentication method used when running Terraform
- When using a service principal, the object_id will be the service principal's object ID
- When using user authentication, the object_id will be the user's object ID
- For CI/CD pipelines, ensure the service principal has appropriate permissions for its intended use
- This module does not create any resources, so it has zero impact on Azure resource limits

## License

This module is licensed under the MIT License. 