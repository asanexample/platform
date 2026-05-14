# Azure Key Vault Module - East US (Dev)

## Overview
This module provisions and configures an Azure Key Vault in the East US region for the development environment. The Key Vault provides secure storage for secrets, keys, and certificates.

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
- **networking**: Uses network configuration for private endpoints

### Key Configuration Settings
- **Key Vault Name**: Uses fixed naming with a unique suffix (vip-dev-eus-kv01)
- **Access Model**: RBAC authorization enabled
- **SKU**: Premium for HSM support
- **Purge Protection**: Enabled with 90-day retention
- **Network Access**:
  - Default network action: Deny
  - Bypass: AzureServices
  - IP Rules: Limited to specific trusted IPs
  - Virtual Network Rules: Access from specific subnets
- **Private Endpoint**:
  - Subnet: endpoints (10.0.30.0/24)
  - Private DNS Zone: privatelink.vaultcore.azure.net

### Security Features
- **Threat Protection**:
  - Microsoft Defender for Key Vault enabled
  - Advanced Threat Protection for anomaly detection
- **Access Policies**:
  - RBAC model for granular access control
  - Managed identities for authentication rather than service principals
- **Auditing and Monitoring**:
  - Diagnostic logs sent to Log Analytics
  - Azure Monitor alerts for suspicious activities

### Managed Keys and Secrets
The module provisions:
- **Keys**:
  - disk-encryption-key: Used for disk encryption
  - application-encryption-key: Used for application-level encryption
- **Secrets**:
  - Database connection strings
  - API keys
  - Service credentials
- **Certificates**:
  - TLS certificates for secure communications

## Implementation Details
The Key Vault is implemented with private endpoint access, making it only accessible from within the virtual network. This enhances security by eliminating direct exposure to the public internet while allowing services within the VNet to securely access secrets.

## Usage Example

To apply this module:
```bash
cd key_vault
terragrunt apply
```

To retrieve a secret (with proper access):
```bash
az keyvault secret show --name my-secret --vault-name vip-dev-eus-kv01
```

## Dependencies on this Module
The following services depend on this Key Vault:
- AKS: For Kubernetes secrets provider integration (CSI driver)
- Azure VMs: For disk encryption
- Applications: For secure secret retrieval
- Infrastructure: For certificate and credential management 