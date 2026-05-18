# Infrastructure Scripts

This directory contains utility scripts for the infrastructure codebase.

## Scaffold Region Script

The `scaffold_region.sh` script is used to create a new region in the infrastructure codebase. It leverages the templates in the `infra/live/{cloud}/_templates/region` directory to create a consistent region structure.

### Usage

```bash
./scaffold_region.sh [options] <environment> <region> <cloud> [cidr_range]
```

#### Arguments

- `environment`: The environment name (e.g., dev, staging, prod)
- `region`: The region name (e.g., westus, eastus, us-west-1)
- `cloud`: The cloud provider (azure, aws, gcp)
- `cidr_range`: Optional CIDR range for the region (e.g., 10.0.0.0/16). If not provided, a default will be calculated based on the environment.

#### Options

- `-d, --dry-run`: Show what would be done without making changes
- `-c, --commit`: Automatically commit changes to git
- `-i, --init`: Automatically initialize the new region
- `-v, --verbose`: Display more information during execution
- `-t, --templates`: Specify an alternative templates directory
- `-h, --help`: Display help message and exit

#### Examples

```bash
# Create a new region with a specific CIDR range
./scaffold_region.sh dev westus azure 10.1.0.0/16

# Dry run to see what changes would be made
./scaffold_region.sh --dry-run prod us-west-1 aws

# Create a new region and automatically commit and initialize
./scaffold_region.sh --commit --init staging europe-west1 gcp
```

### What It Does

The script:

1. Creates the region directory structure in `infra/live/{cloud}/{environment}/{region}/`
2. Copies and configures the `region.hcl` file with the region name and abbreviation
3. Creates the `network.hcl` file with the appropriate CIDR range
4. Creates the `env.hcl` file if it doesn't exist
5. Copies all module templates from `infra/live/{cloud}/_templates/region/*` to the new region
6. Creates a `README.md` file for the region with appropriate documentation

### Templates

The script uses templates from the `infra/live/{cloud}/_templates/region` directory. Each module template contains:

- A `terragrunt.hcl` file that includes locals, root configurations, dependencies, and inputs
- Any other files needed for the module

The templates ensure that all regions have a consistent structure and configuration.

## Other Scripts

(Other scripts information would go here) 