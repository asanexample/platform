# Azure Key Vault Module - West US (Dev)

## Overview
This module provisions and configures an Azure Key Vault in the West US region for the development environment. The Key Vault provides secure storage for secrets, keys, and certificates.

## Configuration Details

### Purpose
Creates a secure Azure Key Vault that:
- Stores sensitive information for applications and infrastructure
- Provides centralized secret management
- Implements appropriate network and access controls
- Enables secure encryption of resources

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group
- **network**: Uses network configuration for private endpoints

### Key Configuration Settings
- **Key Vault Name**: Uses fixed naming with a unique suffix (vipdevwuskv01)
- **Access Model**: RBAC authorization enabled
- **Network Access**:
  - Default network action: Deny
  - Bypass: Azure Services
  - Private endpoint connectivity
- **Private Endpoint**:
  - Subnet: az1-endpoints
  - Private DNS Zone: privatelink.vaultcore.azure.net
- **Encryption Keys**:
  - Disk Encryption Key created: disk-encryption-key

## Usage Example

To apply this module:
```bash
cd key_vault
terragrunt apply
```

## Dependencies on this Module
The following modules may depend on outputs from this module:
- aks_core
- Any module that requires secure secret storage 