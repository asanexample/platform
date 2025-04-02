# Azure Front Door Private Link - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for deploying and managing Azure Front Door Private Link in the East US region for the development environment. This module configures private connectivity between Azure Front Door and backend services like Storage Accounts, securing traffic within the Azure network.

## Configuration Details

### Purpose

This configuration:
- Creates a secure private connection between Azure Front Door and backend services
- Routes traffic through Azure's private backbone network instead of the public internet
- Protects backend services from direct internet exposure
- Enables private origin serving with global Front Door distribution
- Configures routing rules for content delivery with caching

### Dependencies

This configuration depends on:
- **naming**: Uses standardized resource naming conventions
- **frontdoor_endpoint**: References the Front Door endpoint and origin group
- **storage**: Connects to the storage account as a private origin

### Key Configuration Settings

- **Private Link Configuration**:
  - Origin Name: Follows naming convention from the naming module
  - Private Link Request Message: Custom message for connection approval
  - Storage Integration: Configured to use the Blob storage endpoint
  - Storage Account: References the existing storage account

- **Route Configuration**:
  - Route Enabled: true
  - Route Name: Follows naming convention from the naming module
  - Patterns to Match: ["/*"] (all paths)
  - Forwarding Protocol: HttpsOnly for secure communication

- **Caching Configuration**:
  - Cache Enabled: true
  - Query String Caching Behavior: IgnoreQueryString
  - Compression Enabled: true
  - Content Types to Compress: Common web content types (JSON, HTML, CSS, JavaScript)

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/frontdoor_private_link
terragrunt plan
terragrunt apply
```

To verify the private link connection after deployment:

```bash
az network private-endpoint-connection list --resource-group $(terragrunt output storage_resource_group_name) --name $(terragrunt output storage_account_name) --type Microsoft.Storage/storageAccounts
```

## Dependencies on this Configuration

The following modules may depend on outputs from this configuration:
- Any module that needs to reference the Front Door routes or origins
- Frontend applications that need to access the private backend through Front Door

## Implementation Notes

The Private Link integration ensures that traffic between Front Door and the backend storage remains on the Microsoft network backbone, never traversing the public internet. This enhances security for sensitive workloads.

The caching configuration is optimized for web content, which improves performance and reduces backend load. The cache settings can be adjusted based on the specific requirements of your application.

In a production environment, consider implementing WAF policies and custom domain configurations to further enhance security and usability. 