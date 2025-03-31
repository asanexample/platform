# Front Door Profile - Development (East US)

This module deploys an Azure Front Door Profile in the Development environment (East US region).

## Configuration

- **Status**: Enabled
- **SKU**: Premium_AzureFrontDoor (supports Private Link)
- **Response Timeout**: 60 seconds

## Dependencies

- **Resource Group**: Uses the shared resource group
- **Naming Module**: Uses standard naming conventions for resources

## Usage

To apply this configuration:

```bash
cd infra/live/azure/dev/eastus/frontdoor_profile
terragrunt apply
```

## Related Resources

This profile is the parent resource for:
- Front Door Endpoint
- Front Door Origin Group 
- Front Door Origin (Private Link)
- Front Door Route 