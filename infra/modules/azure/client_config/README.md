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

## Outputs

| Name | Description |
|------|-------------|
| client_id | The client ID (application ID) of the current Azure client |
| tenant_id | The tenant ID of the current Azure client |
| subscription_id | The subscription ID of the current Azure client |
| object_id | The object ID of the current Azure client (user or service principal) |

## Notes

- This module is often used in conjunction with role assignment resources or modules
- The values returned depend on the authentication method used when running Terraform
- When using a service principal, the object_id will be the service principal's object ID
- When using user authentication, the object_id will be the user's object ID 