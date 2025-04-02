# Azure Client Config - West US (Ops)

## Overview

This directory contains the Terragrunt configuration for retrieving the current Azure client configuration (subscription, tenant, etc.) in the West US region for the operations environment. This module is used as a dependency by other modules that need information about the current Azure client context.

## Configuration Details

### Purpose

This configuration:
- Retrieves information about the current Azure client context
- Provides outputs such as client ID, object ID, subscription ID, and tenant ID
- Acts as a utility module for other modules to access Azure client information
- Enables other modules to implement identity-aware configurations without hardcoding identifiers

### Dependencies

This configuration has no dependencies on other modules.

### Key Configuration Settings

- **Client Config Data**:
  - Returns client_id: The ID of the client used for authentication
  - Returns object_id: The object ID of the authenticated principal
  - Returns subscription_id: The current subscription ID
  - Returns tenant_id: The current tenant ID

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/ops/westus/client_config
terragrunt plan
terragrunt apply
```

To view the client configuration information:

```bash
cd infra/live/azure/ops/westus/client_config
terragrunt output
```

## Dependencies on this Configuration

The following modules depend on outputs from this configuration:
- storage_roles
- key_vault (for access policies)
- Any module that requires the current user's identity information

## Implementation Notes

This module is a lightweight wrapper around the Azure provider's data source for client configuration. It doesn't create any actual resources but instead retrieves data about the current authenticated context. It should be applied before any modules that depend on the current client's identity information.

For operations environments, this information is especially critical as it's used to configure proper security context for operational resources and administrative access controls. 