# Front Door Private Link - Operations (West US)

This module defines an Azure Front Door Private Link Origin in the Operations environment (West US region), but it is explicitly disabled as it depends on the Front Door Endpoint which is disabled in this environment.

## Configuration

- **Status**: Disabled (inherits from Front Door Endpoint)
- **Origin**: Configured but inactive
- **Storage Link**: Configured but inactive
- **Route**: Configured but inactive
- **Caching**: Advanced caching configuration (inactive)

## Dependencies

- **Front Door Endpoint**: Disabled in West US (inherits disabled state)
- **Storage Account**: References the ops westus storage account
- **Resource Group**: Uses the shared resource group
- **Naming Module**: Uses standard naming conventions for resources

## Usage

To apply this configuration:

```bash
cd infra/live/azure/ops/westus/frontdoor_private_link
terragrunt apply
```

## Why Disabled?

The Front Door Private Link is disabled in the Operations West US environment because:
- Front Door resources are managed globally and only need to be deployed in one region
- The Front Door Endpoint it depends on is disabled in this environment
- The East US region serves as the primary region for Front Door resources

## Related Resources

When enabled, this module would create:
- A Front Door Origin with Private Link to storage
- A Front Door Route with advanced caching configuration 