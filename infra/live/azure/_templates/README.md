# Terragrunt Templates

This directory contains templates for creating new environments and regions in the Azure infrastructure.

## Directory Structure

- `region/`: Templates for creating new regions within existing environments
- `environment/`: Templates for creating new environments (e.g., prod, staging, qa)

## Using Templates with the Scaffold Script

The templates in this directory are designed to work with the `scaffold_region.sh` script located in the `scripts/` directory of the repository. This script automates the process of creating new regions based on these templates.

### Creating a New Region

To create a new region using the scaffold script:

```bash
# From the repository root
./scripts/scaffold_region.sh [options] <environment> <region> azure [cidr_range]
```

For example:

```bash
# Create eastus2 region in the dev environment
./scripts/scaffold_region.sh dev eastus2 azure

# Create westeurope with a specific CIDR range
./scripts/scaffold_region.sh prod westeurope azure 10.2.0.0/24
```

See `scripts/README.md` for complete documentation on the scaffold script.

### Creating a New Region Manually

If you prefer to create a new region manually:

1. Create a directory for the new region: `infra/live/azure/<environment>/<region>/`
2. Copy the region.hcl, network.hcl, and other configuration files from the templates:
   ```bash
   cp -r infra/live/azure/_templates/region/region.hcl infra/live/azure/<environment>/<region>/
   cp -r infra/live/azure/_templates/region/network.hcl infra/live/azure/<environment>/<region>/
   ```
3. Update the copied files with the correct values for the new region:
   - In `region.hcl`: Update region and region_abbv
   - In `network.hcl`: Update the CIDR range
4. Copy each module directory from the templates and update as needed:
   ```bash
   cp -r infra/live/azure/_templates/region/resource_group infra/live/azure/<environment>/<region>/
   cp -r infra/live/azure/_templates/region/naming infra/live/azure/<environment>/<region>/
   # ... and so on for other modules
   ```

### Creating a New Environment

For creating a new environment, copy the templates from the environment directory:

```bash
# Create a new environment structure
mkdir -p infra/live/azure/<new_environment>
cp infra/live/azure/_templates/environment/env.hcl infra/live/azure/<new_environment>/
```

Then update the env.hcl file with the appropriate environment name.

## Template Customization

If you need to customize templates:

1. Modify the templates in this directory
2. The scaffold script will use these updated templates for all new regions

### Best Practices

- Keep template files consistent and DRY
- Use placeholder variables like `__REGION__` and `__CIDR_RANGE__` in templates
- Maintain consistent dependencies between modules
- Organize terraform modules in a logical sequence 