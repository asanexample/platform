# Front Door Profile - Operations (West US)

This module defines an Azure Front Door Profile in the Operations environment (West US region), but it is explicitly disabled in this environment.

## Configuration

- **Status**: Disabled
- **SKU**: Premium_AzureFrontDoor (supports Private Link and WAF) - inactive
- **Response Timeout**: 120 seconds - inactive

## Dependencies

- **Resource Group**: Uses the shared resource group
- **Naming Module**: Uses standard naming conventions for resources

## Usage

To apply this configuration:

```bash
cd infra/live/azure/ops/westus/frontdoor_profile
terragrunt apply
```

## Why Disabled?

The Front Door profile is explicitly disabled in the Operations West US environment for the following reasons:
- Front Door resources are managed globally and only need to be deployed in one region
- The East US region serves as the primary region for Front Door resources
- Disabling in West US prevents duplicate Front Door resources and potential conflicts

## Related Resources

When enabled, this profile would be the parent resource for:
- Front Door Endpoint
- Front Door Origin Group 
- Front Door Origin (Private Link)
- Front Door Route

## Production Notes

The Premium SKU is used in the Operations environment to support:
- Advanced security features
- Private Link origins
- Web Application Firewall (WAF) policies
- Enhanced reliability with longer timeout settings 