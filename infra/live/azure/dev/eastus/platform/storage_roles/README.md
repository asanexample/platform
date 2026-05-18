# Azure Storage Roles - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for managing Azure RBAC role assignments for Storage Accounts in the East US region for the development environment. This module configures appropriate permissions for users and service principals to access the storage account and its data.

## Configuration Details

### Purpose

This configuration:
- Assigns appropriate RBAC roles to users and service principals for storage access
- Configures data access roles for Blob storage operations
- Ensures least privilege access principles are followed
- Enables automated access to storage resources for development purposes
- Centralizes storage access management in a dedicated module

### Dependencies

This configuration depends on:
- **client_config**: Retrieves current user identity information
- **storage**: References the storage account for role assignments

### Key Configuration Settings

- **Role Assignments**:
  - Storage Blob Data Contributor: Assigned to the current user
  - Storage Blob Data Owner: Assigned to the current user
  - Additional roles can be added for service principals and other users

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/storage_roles
terragrunt plan
terragrunt apply
```

To view the configured role assignments after deployment:

```bash
az role assignment list --scope $(terragrunt output storage_account_id) --query "[].{principalName:principalName, roleDefinitionName:roleDefinitionName, scope:scope}"
```

## Dependencies on this Configuration

Other modules generally don't depend on this module's outputs. This module primarily exists to ensure appropriate access to the storage account created by the storage module.

## Implementation Notes

This module separates role assignments from the storage account creation to maintain clear separation of concerns. It's important to note that the current implementation assigns powerful roles (Contributor and Owner) to the current user for development purposes. 

For production environments, follow these best practices:
1. Limit the number of users with Storage Blob Data Owner role
2. Use custom roles with minimum required permissions where possible
3. Regularly audit and rotate access permissions
4. Consider using Azure AD groups for role assignments rather than individual users
5. Implement time-limited role assignments for temporary access needs

The module is designed to be compatible with different storage account configurations and can be expanded to manage roles for other Azure resources as needed. 