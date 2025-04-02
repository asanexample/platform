# Azure Private DNS Zones - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for deploying and managing Azure Private DNS Zones in the East US region for the development environment. These Private DNS Zones enable name resolution for private Azure services like Storage, Key Vault, and other services accessed through Private Link.

## Configuration Details

### Purpose

This configuration:
- Creates Private DNS Zones for Azure PaaS services accessed via Private Link
- Links the DNS zones to the virtual network for name resolution
- Enables secure private connectivity to Azure services
- Eliminates the need for custom DNS configuration for private endpoints

### Dependencies

This configuration depends on:
- **resource_group**: Deploys resources in the specified resource group
- **networking**: Links DNS zones to the virtual network

### Key Configuration Settings

- **Private DNS Zones**:
  - `privatelink.blob.core.windows.net`: For Azure Blob Storage private endpoints
  - `privatelink.file.core.windows.net`: For Azure File Storage private endpoints
  - `privatelink.vaultcore.azure.net`: For Azure Key Vault private endpoints

- **Virtual Network Links**:
  - Each DNS zone is linked to the main virtual network
  - Auto-registration is disabled (manual endpoint registration)
  - Link names follow naming convention with service type prefix

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/dns
terragrunt plan
terragrunt apply
```

To verify the DNS zone links after deployment:

```bash
az network private-dns link vnet list --resource-group $(terragrunt output resource_group_name)
```

## Dependencies on this Configuration

The following modules depend on outputs from this configuration:
- storage (for private endpoint DNS integration)
- key_vault (for private endpoint DNS integration)
- Any module that creates private endpoints that need DNS resolution

## Implementation Notes

Private DNS Zones are a critical component for Private Link integration. They enable services to be resolved using their public DNS names while routing traffic privately within the Azure network. This configuration only creates the zones and links them to the virtual network; the actual DNS A records are created automatically when private endpoints are created in other modules.

For a production environment, consider centralizing DNS zones in a hub network and sharing them across multiple spoke networks through virtual network links. 