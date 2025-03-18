# Multi-Region Deployment Guide

This document outlines the approach for deploying infrastructure across multiple Azure regions using Terragrunt.

## Hosting Infrastructure Deployment

The hosting module combines networking and storage resources to provide a complete infrastructure foundation for applications. This section covers how to deploy hosting infrastructure to multiple regions.

### Available Regions

The infrastructure is currently deployed to the following regions:

| Environment | Regions                   |
|-------------|---------------------------|
| Dev         | East US, West US          |
| Test        | (Reserved for future use) |
| Prod        | (Reserved for future use) |

### Deployment Command Reference

#### Validating Changes

Before applying any changes, it's recommended to run a plan to validate the changes:

```bash
# Plan changes for a specific region
cd /Users/josh/centric/platform/infra/live/azure/dev/eastus/hosting
terragrunt plan

# Plan changes for all hosting modules across all regions
cd /Users/josh/centric/platform/infra/live/azure/dev
terragrunt run-all plan --terragrunt-include-dir "*/hosting"
```

#### Applying Changes

To apply changes to hosting infrastructure:

```bash
# Deploy to a single region
cd /Users/josh/centric/platform/infra/live/azure/dev/eastus/hosting
terragrunt apply

# Deploy to all regions simultaneously
cd /Users/josh/centric/platform/infra/live/azure/dev
terragrunt run-all apply --terragrunt-include-dir "*/hosting"
```

### Adding a New Region

To deploy hosting infrastructure to a new region, follow these steps:

1. **Create directory structure**:
   ```bash
   mkdir -p /Users/josh/centric/platform/infra/live/azure/dev/new-region/hosting
   ```

2. **Copy the template**:
   ```bash
   cp /Users/josh/centric/platform/infra/live/azure/_envcommon/region-hosting.hcl.template \
      /Users/josh/centric/platform/infra/live/azure/dev/new-region/hosting/terragrunt.hcl
   ```

3. **Update CIDR allocations**:
   - Refer to the CIDR allocation strategy in `infra/docs/cidr-allocation.md`
   - Update the mock outputs in the `dependency "networking"` block with the appropriate CIDR ranges

4. **Configure region-specific settings**:
   - Update any region-specific configurations in the `inputs` block
   - Add the region code to the `region_code_map` if it's not already there

5. **Validate and apply**:
   ```bash
   cd /Users/josh/centric/platform/infra/live/azure/dev/new-region/hosting
   terragrunt validate
   terragrunt plan
   terragrunt apply
   ```

### Dependencies

The hosting module has dependencies on:

1. **Networking infrastructure**: Must be deployed before hosting
   - VNet and subnets must exist before hosting can reference them
   - The terragrunt configuration includes dependencies to ensure the correct order
   - Mock outputs are provided to enable planning without existing dependencies

### Resource Naming Conventions

Resources deployed by the hosting module follow the naming conventions defined in `infra/docs/NAMING_CONVENTIONS.md`:

- Resource Groups: `vip-rg-{env}-{region_code}-hosting`
- Storage Accounts: `vip{env}{region_code}sa001`
- Containers: Standard container names (`assets`, `public`, `pdf`)

## Troubleshooting

### Common Issues

1. **Dependency Errors**:
   - Error: `Error: Unable to find remote state`
   - Resolution: Ensure the networking module has been applied first, or use `--terragrunt-ignore-dependency-errors` for initial planning

2. **Authentication Issues**:
   - Error: `Error: Error building account: obtaining subscription(s): authorization error`
   - Resolution: Run `az login` to authenticate with Azure

### Getting Help

For additional assistance:

- Review the module documentation in the code comments
- Refer to the testing examples in `infra/tests/modules/azure/hosting`
- Check the Terragrunt error handling guide at https://terragrunt.gruntwork.io/docs/reference/cli-options/ 