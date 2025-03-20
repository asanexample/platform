# Region Scaffolding

This document describes the region scaffolding process for the VIP Platform, which automates the creation of new regional infrastructure configurations based on standardized templates.

## Overview

When expanding the VIP Platform to a new region, manually creating all the necessary infrastructure configurations can be time-consuming and error-prone. The region scaffolding tool automates this process by:

1. Creating the necessary directory structure for a new region
2. Setting up region-specific configurations with appropriate values
3. Generating CIDR blocks and subnet allocations based on a standardized pattern
4. Creating a README.md file with deployment instructions

## Prerequisites

- Template directory structure (if using custom templates)
- Terraform and Terragrunt installed
- CIDR allocations properly documented in the `allocations.csv` file

## Using the Region Scaffolding Tool

### Via Makefile

The simplest way to scaffold a new region is using the `scaffold-region` Makefile target:

```bash
make scaffold-region CLOUD=azure TARGET_REGION=eastus ENV=dev REGION_ABBV=east
```

This command will:
1. Create a new region configuration for the specified cloud provider in the target region
2. Update region-specific values (like region names and CIDR blocks)
3. Create appropriate module directories and configurations
4. Generate a README.md file with deployment instructions

#### Available Cloud Providers

The tool supports the following cloud providers:

- `azure`: Microsoft Azure (e.g., regions like eastus, westus)
- `aws`: Amazon Web Services (e.g., regions like us-east-1, us-west-2)
- `gcp`: Google Cloud Platform (e.g., regions like us-east1, us-central1)

#### Required Parameters

- `CLOUD`: The cloud provider (azure, aws, gcp)
- `TARGET_REGION`: The region to scaffold (e.g., eastus, us-east-1)
- `ENV`: The environment (e.g., dev, test, prod)
- `REGION_ABBV`: The abbreviation used for the region (e.g., east, west)

#### Additional Options

The scaffold-region target supports additional options:

```bash
# Dry run mode - show what would be done without making changes
make scaffold-region CLOUD=azure TARGET_REGION=eastus ENV=dev REGION_ABBV=east DRY_RUN=true
```

### Directly Using the Script

You can also use the script directly with the new command-line format:

```bash
# Basic usage
./scripts/scaffold_region.sh --cloud azure --target-region eastus --environment dev --region-abbv east

# With dry-run option
./scripts/scaffold_region.sh --cloud azure --target-region eastus --environment dev --region-abbv east --dry-run
```

## Using Templates

The scaffolding tool supports both standard modules generation and template-based scaffolding.

### Standard Module Generation

The tool will automatically create standard module directories with properly configured terragrunt.hcl files. These files include:
- Local variables loading common configuration
- Dependencies between modules
- Appropriate inputs for each module
- Standardized naming and resource configuration

The following modules are created based on the cloud provider:

- **Azure**: resource_group, naming, networking, key_vault, storage, aks_identity, aks_core, aks_node_pools
- **AWS**: vpc, subnets, security_groups, s3, eks_cluster, eks_node_groups
- **GCP**: vpc, subnets, firewall_rules, storage, gke_cluster, gke_node_pools

### Custom Templates

For more sophisticated scaffolding, you can create custom templates in the following structure:

```
infra/templates/
├── azure/
│   └── modules/
│       ├── resource_group/
│       ├── networking/
│       └── ...
├── aws/
│   └── modules/
│       ├── vpc/
│       ├── subnets/
│       └── ...
└── gcp/
    └── modules/
        ├── vpc/
        ├── subnets/
        └── ...
```

Template files can include the following placeholder variables:

- `__REGION__`: Will be replaced with the target region name
- `__ENVIRONMENT__`: Will be replaced with the environment name
- `__CLOUD__`: Will be replaced with the cloud provider name
- `__CIDR_RANGE__`: Will be replaced with the appropriate CIDR range
- `__REGION_ABBV__`: Will be replaced with the region abbreviation

## What Gets Scaffolded

The scaffolding process:

1. Creates the target region directory with the appropriate structure
2. Generates `region.hcl` with the correct region name and abbreviation
3. Creates or reuses `env.hcl` for environment-specific configuration
4. Generates `network.hcl` with appropriate CIDR blocks and subnet allocations
5. Creates module directories with terragrunt.hcl files that include proper dependencies and inputs
6. Generates a README.md file with information about the modules and deployment order

## After Scaffolding

After scaffolding a new region, you should:

1. Review the generated files and make any necessary adjustments
2. Verify that CIDR allocations are correct in `network.hcl`
3. Initialize and plan the new region to check for any issues:

```bash
make init-region ENV=dev REGION=eastus CLOUD=azure
make plan-region ENV=dev REGION=eastus CLOUD=azure
```

4. Apply the infrastructure in the correct order (as specified in the generated README.md), or use the apply-region target:

```bash
make apply-region ENV=dev REGION=eastus CLOUD=azure
```

## CIDR Allocation

The scaffolding tool automatically determines the correct CIDR blocks for the new region by:

1. Reading from the `allocations.csv` file if available
2. Falling back to default values if the file doesn't exist or the region isn't found

The default CIDR block allocation follows this pattern:

- **Azure**: 10.200.x.0/21
- **AWS**: 10.100.x.0/21
- **GCP**: 10.300.x.0/21

Where 'x' varies by region.

## Customization

If you need to customize the scaffolding process, you can:

1. Create custom templates in the `infra/templates` directory
2. Modify the `scripts/scaffold_region.sh` script to handle additional use cases
3. Update the CIDR allocation logic to follow your organization's IP addressing scheme

## Troubleshooting

If you encounter issues during the scaffolding process:

1. Check that the cloud provider and region combination is valid
2. Verify that the `allocations.csv` file is correctly formatted with the proper CIDR blocks
3. Ensure you have the necessary permissions to create directories and files
4. Check for any error messages in the script output
5. Try the `--dry-run` option to see what would be created without making changes

## Limitations

- The scaffolding tool doesn't handle state migration or resource creation
- Some very region-specific configurations might need manual adjustment
- The tool generates a basic set of module directories, but detailed module configurations require templates

## Best Practices

- Create comprehensive templates for each cloud provider for consistent scaffolding
- Use placeholder variables in templates for maximum flexibility
- Always review the scaffolded files before initializing and applying
- Use version control to track changes and enable rollback if needed
- Test the new region deployment in a non-production environment first
- Keep the `allocations.csv` file up to date with all CIDR allocations 