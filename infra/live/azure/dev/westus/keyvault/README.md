# Azure Key Vault Terragrunt Configuration

This directory contains the Terragrunt configuration for deploying an Azure Key Vault in the West US region. The Key Vault provides secure storage for secrets, keys, and certificates used by other Azure resources.

## Configuration Overview

The Key Vault is configured with:

- RBAC authorization enabled for simplified access management
- Disk encryption capabilities enabled for integration with Azure Disk Encryption
- Network restrictions limiting access to specific subnets
- Private endpoint integration for secure access from within the VNet
- A unique name with a static suffix to avoid naming conflicts

## Naming Strategy

The Key Vault uses a fixed unique suffix naming strategy to ensure:

1. The name is globally unique across Azure (required for Key Vaults)
2. The name remains consistent between deployments (no recreation on apply)

```hcl
locals {
  # Use a fixed unique suffix instead of timestamp
  unique_suffix = "01"
}

# Use a fixed unique name that doesn't change on every apply
name = "vipdevwuskv${local.unique_suffix}"
```

Previously, a timestamp-based naming approach was used which caused the Key Vault to be recreated on each apply:

```hcl
# This approach is no longer used
timestamp_suffix = formatdate("hhmmss", timestamp())
name = "vipdeveuskv${local.timestamp_suffix}"
```

## Network Configuration

The Key Vault is configured with strict network access controls:

- Public network access is disabled
- Only Azure services and resources within specific subnets can access the Key Vault
- A private endpoint is created in a dedicated subnet (`az1-endpoint-subnet`)

## Dependencies

This module has dependencies on:

- **naming**: For standardized resource naming
- **resource_group**: For the resource group where the Key Vault is deployed
- **networking**: For subnet IDs used in network rules and private endpoint

## Applying Changes

To apply changes to the Key Vault configuration:

```bash
cd infra/live/azure/dev/westus/keyvault
terragrunt plan
terragrunt apply
```

## Outputs

After deployment, the following outputs are available:

- **id**: The full resource ID of the Key Vault
- **name**: The name of the Key Vault (`vipdevwuskv01`)
- **uri**: The URI used to access the Key Vault
- **tenant_id**: The Azure AD tenant ID associated with the Key Vault
- **access_policy_ids**: IDs of any access policies (empty with RBAC)
- **private_endpoint_ids**: IDs of the private endpoint created for the Key Vault 