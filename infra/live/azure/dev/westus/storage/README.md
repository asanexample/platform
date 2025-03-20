# Azure Storage Module - West US (Dev)

## Overview
This module provisions and configures Azure Storage Accounts and Containers in the West US region for the development environment. It sets up secure storage with appropriate access controls and network restrictions.

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
- **network**: Uses network configuration for service endpoints and private endpoints

### Key Configuration Settings
- **Storage Account Settings**:
  - Account Tier: Standard
  - Replication: LRS (Locally Redundant Storage) for development
  - Secure transfer required: Enabled
  - Public network access: Restricted to specific IPs/networks
  - Network Rules:
    - Default action: Deny
    - Virtual network rules: Enabled for specific subnets
    - Bypass: AzureServices
- **Containers**:
  - Multiple containers with specified access types
  - Container-level lifecycle policies

### Private Endpoint Configuration
- Private endpoint enabled for secure internal access
- Connected to the endpoints subnet in the VNet
- Integrated with private DNS zones

## Usage Example

To apply this module:
```bash
cd storage
terragrunt apply
```

## Dependencies on this Module
The following modules may depend on outputs from this module:
- Any module requiring persistent storage
- Applications using blob storage 