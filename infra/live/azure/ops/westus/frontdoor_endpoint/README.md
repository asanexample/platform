# Front Door Endpoint - Operations (West US)

This module defines an Azure Front Door Endpoint and Origin Group in the Operations environment (West US region), but it is explicitly disabled as it depends on the Front Door Profile which is disabled in this environment.

## Configuration

- **Status**: Disabled (inherits from Front Door Profile)
- **Origin Group**: Configured but inactive
- **Load Balancing**: Configured but inactive
- **Health Probe**: Configured but inactive

## Dependencies

- **Front Door Profile**: Disabled in West US (inherits disabled state)
- **Resource Group**: Uses the shared resource group
- **Naming Module**: Uses standard naming conventions for resources

## Usage

To apply this configuration:

```bash
cd infra/live/azure/ops/westus/frontdoor_endpoint
terragrunt apply
```

## Why Disabled?

The Front Door endpoint is disabled in the Operations West US environment because:
- Front Door resources are managed globally and only need to be deployed in one region
- The Front Door Profile it depends on is disabled in this environment
- The East US region serves as the primary region for Front Door resources

## Related Resources

When enabled, this module would create:
- A Front Door Endpoint
- A Front Door Origin Group with load balancing and health probe settings 