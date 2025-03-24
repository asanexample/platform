# Azure Storage Module - East US (Dev)

## Overview
This module provisions and configures Azure Storage Accounts and Containers in the East US region for the development environment. It sets up secure storage with appropriate access controls and network restrictions.

## Configuration Details

### Purpose
Creates a storage infrastructure that:
- Provides secure blob storage for application and infrastructure data
- Implements appropriate network access controls
- Configures containers with specific access levels
- Enables proper lifecycle management for data

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group
- **networking**: Uses network configuration for service endpoints and private endpoints

### Key Configuration Settings
- **Storage Account Settings**:
  - Account Kind: StorageV2
  - Account Tier: Standard
  - Replication: ZRS (Zone Redundant Storage) for high availability
  - Access Tier: Hot
  - Secure transfer required: Enabled
  - Public network access: Restricted to specific IPs/networks
  - Hierarchical Namespace: Disabled
  - Network Rules:
    - Default action: Deny
    - Virtual network rules: Enabled for specific subnets (az1-nodes, az2-nodes, az3-nodes)
    - Bypass: AzureServices
- **Containers**:
  - logs: For application logging (private access)
  - backups: For critical data backups (private access)
  - state: For application state data (private access)
  - media: For media assets (private access)

### Security Features
- **Encryption**:
  - Storage Service Encryption enabled by default
  - Customer-managed keys option available
- **Access Control**:
  - Managed Identity access via Storage Blob Data Reader/Contributor roles
  - Shared Access Signatures (SAS) for time-limited access
  - No public access to any containers
- **Threat Protection**:
  - Microsoft Defender for Storage enabled
  - Advanced Threat Protection with alerts

### Private Endpoint Configuration
- Private endpoint enabled for secure internal access
- Connected to the endpoints subnet (10.0.30.0/24) in the VNet
- Integrated with private DNS zone for blob.core.windows.net

## Data Lifecycle Management
- Automatic transition to cool storage tier after 90 days
- Automatic deletion of data in "logs" container after 1 year
- Snapshot and soft delete policies for data protection

## Implementation Details
The storage module configures Zone Redundant Storage (ZRS) to ensure data availability across all East US availability zones. This provides 99.9999% durability and 99.99% availability, protecting against zone-level failures.

## Usage Example

To apply this module:
```bash
cd storage
terragrunt apply
```

To view the storage account and container details:
```bash
cd storage
terragrunt output storage_account_details
```

## Dependencies on this Module
The following services depend on this storage infrastructure:
- AKS persistent volumes via CSI driver
- Azure Functions for state management
- Log Analytics for log archiving
- ETL processes for data processing 