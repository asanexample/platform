# Azure Private DNS Zones - West US (Ops)

## Overview

This directory contains the Terragrunt configuration for deploying and managing Azure Private DNS Zones in the West US region for the operations environment. These Private DNS Zones enable name resolution for private Azure services like Storage, Key Vault, and other services accessed through Private Link.

## Configuration Details

### Purpose

This configuration:
- Creates Private DNS Zones for Azure PaaS services accessed via Private Link
- Links the DNS zones to the virtual network for name resolution
- Enables secure private connectivity to Azure services
- Eliminates the need for custom DNS configuration for private endpoints
- Ensures operational workloads can securely access Azure services

### Dependencies

This configuration depends on:
- **resource_group**: Deploys resources in the specified resource group
- **networking**: Links DNS zones to the virtual network

### Key Configuration Settings

- **Private DNS Zones**:
  - `privatelink.blob.core.windows.net`: For Azure Blob Storage private endpoints
  - `privatelink.file.core.windows.net`: For Azure File Storage private endpoints
  - `privatelink.vaultcore.azure.net`: For Azure Key Vault private endpoints
  - Other service-specific DNS zones as needed for operational workloads

- **Virtual Network Links**:
  - Each DNS zone is linked to the main virtual network
  - Auto-registration is disabled (manual endpoint registration)
  - Link names follow naming convention with service type prefix
  - Configured for operational network isolation

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/ops/westus/dns
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
- Any operational services that create private endpoints that need DNS resolution

## Implementation Notes

Private DNS Zones are a critical component for Private Link integration in operational environments. They enable services to be resolved using their public DNS names while routing traffic privately within the Azure network. This configuration only creates the zones and links them to the virtual network; the actual DNS A records are created automatically when private endpoints are created in other modules.

For operations environments, these DNS zones should be strictly controlled and monitored as they form a critical part of the network security architecture. Consider implementing DNS analytics and monitoring for security and operational insights.

In multi-region deployments with a hub-spoke architecture, consider centralizing DNS zones in a hub network and sharing them across multiple spoke networks through virtual network links to reduce management overhead and ensure consistency. 