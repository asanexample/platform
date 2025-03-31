# Front Door Profile - Operations (West US)

This module deploys an Azure Front Door Profile in the Operations environment (West US region).

## Configuration

- **SKU**: Premium_AzureFrontDoor (supports Private Link and WAF)
- **Response Timeout**: 120 seconds

## Dependencies

- **Resource Group**: Uses the shared resource group
- **Naming Module**: Uses standard naming conventions for resources

## Usage

To apply this configuration:

```bash
cd infra/live/azure/ops/westus/frontdoor_profile
terragrunt apply
```

## Related Resources

This profile is the parent resource for:
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