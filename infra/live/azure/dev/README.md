# Azure Development Environment

This directory contains the Terragrunt configurations for the Azure development environment.

## Environment Configuration

The environment configuration is consolidated in a single file `common.hcl`, which includes:

- Environment variables (`env`, `environment`, `prefix`, etc.)
- Subscription name mapping (`subscription_name`)
- Common tags
- Environment-specific tags

For backward compatibility, there is a symbolic link from `env.hcl` to `common.hcl`.

## Configuration Structure

```
dev/
├── common.hcl           # Main configuration file with all environment variables and tags
├── env.hcl -> common.hcl  # Symbolic link for backward compatibility
└── [region]/            # Region-specific configurations
    ├── network.hcl      # Network configuration for this region
    ├── region.hcl       # Region-specific variables
    └── [modules]/       # Module-specific configurations
```

## Subscription Mapping

The environment includes a subscription name mapping that can be used to associate resources with the appropriate Azure subscription:

| Environment | Subscription Name         |
|-------------|---------------------------|
| dev         | innovation-operations     |
| qa/staging  | innovation-test           |
| preprod     | innovation-preprod        |
| prod        | innovation-prod           |

## Usage

To reference the environment configuration in a Terragrunt module:

```hcl
# Load environment variables
locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Access variables
  env               = local.common_vars.locals.env
  subscription_name = local.common_vars.locals.subscription_name
  
  # Access tags
  tags = local.common_vars.locals.tags
}
```

The older pattern using `env.hcl` will continue to work through the symbolic link:

```hcl
locals {
  env_vars = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  
  # These will work as before
  env = local.env_vars.locals.environment
  env_tags = local.env_vars.locals.env_tags
}
``` 