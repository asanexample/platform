# Azure Storage Roles - West US (Ops)

## Overview

This directory contains the Terragrunt configuration for managing Azure RBAC role assignments for Storage Accounts in the West US region for the operations environment. This module configures appropriate permissions for users and service principals to access the storage account and its data, with security controls appropriate for operational workloads.

## Configuration Details

### Purpose

This configuration:
- Assigns appropriate RBAC roles to users and service principals for storage access
- Configures data access roles for Blob storage operations
- Implements strict least privilege access principles
- Enables controlled access to operational storage resources
- Centralizes storage access management in a dedicated module
- Enforces separation of duties for operational data

### Dependencies

This configuration depends on:
- **client_config**: Retrieves current user identity information
- **storage**: References the storage account for role assignments

### Key Configuration Settings

- **Role Assignments**:
  - Storage Blob Data Contributor: Assigned to the current user
  - Storage Blob Data Owner: Assigned to the current user (limited scope)
  - Additional roles for operational service principals
  - Time-limited role assignments (where applicable)

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/ops/westus/storage_roles
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

This module implements a strict access control model appropriate for operational environments. It separates role assignments from the storage account creation to maintain clear separation of concerns and facilitate auditing. 

Security considerations for operational environments include:
1. Strict limits on users with Storage Blob Data Owner role
2. Custom roles with minimum required permissions
3. Automated audit logging of all access
4. Role assignments through Azure AD groups rather than individual users
5. Time-limited role assignments for administrative access
6. Just-in-time access for elevated privileges (when applicable)
7. Regular access reviews to ensure compliance with security policies

The role assignments in this module should be regularly reviewed and audited to ensure that only authorized personnel and services have access to operational data. Consider implementing Azure Policy to enforce compliance with access control requirements. 