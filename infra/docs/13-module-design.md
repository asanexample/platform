# Module Design

## Overview

This document outlines the principles and best practices for designing infrastructure modules within the Reference Platform. Properly structured modules are essential for maintainability, reusability, and consistency across infrastructure deployments.

## Design Principles

Reference Platform modules follow these core design principles:

1. **Single Responsibility**: Each module should have a clear, focused purpose
2. **High Cohesion**: Related resources should be grouped together
3. **Low Coupling**: Minimize dependencies between modules
4. **Clear Interfaces**: Well-defined inputs and outputs
5. **Sensible Defaults**: Provide reasonable default values where appropriate
6. **Complete Documentation**: Comprehensive README with examples and usage guidelines

## Module Structure

All modules follow a consistent structure:

```text
modules/aws/example_module/
├── main.tf           # Primary resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── versions.tf       # Required OpenTofu and provider versions
├── README.md         # Module documentation
├── examples/         # Usage examples
│   └── basic/        # Basic implementation example
└── tests/            # Test configurations
    └── unit/         # Unit tests
```

## Provider Configuration

### Provider Management Best Practices

When configuring providers in modules, follow these guidelines to avoid conflicts, especially when using Terragrunt:

1. **Avoid Explicit Provider Blocks**: Modules should generally not contain explicit `provider` blocks with non-empty configurations, as this can conflict with the caller's provider configuration.

2. **Use Required Providers Block**: Define provider requirements in the `versions.tf` file using the `required_providers` block, but avoid setting configuration values:

   ```hcl
   terraform {
     required_version = ">= 1.6.0"
     required_providers {
       aws = {
         source  = "hashicorp/aws"
         version = "6.47.0"
       }
     }
   }
   ```

3. **Provider Aliases**: If a module needs to use multiple configurations of the same provider, use provider aliases and allow the configuration to be passed in:

   ```hcl
   # In module:
   resource "aws_s3_bucket" "example" {
     provider = aws.alternative
     # ...
   }
   
   # In calling code:
   provider "aws" {
     alias  = "alternative"
     region = "us-west-2"
   }
   
   module "example" {
     source = "./example_module"
     providers = {
       aws.alternative = aws.alternative
     }
   }
   ```

### Terragrunt Provider Configuration

When modules will be used with Terragrunt, follow these additional guidelines:

1. **Remove Explicit Provider Configurations**: Modules should not contain hardcoded provider configurations, as Terragrunt will generate these.

2. **Define Provider Requirements Only**: In the module's `versions.tf` file, only specify the `required_version` and avoid duplicating `required_providers` blocks that may already be defined in the root Terragrunt configuration:

   ```hcl
   # Good practice for modules used with Terragrunt
   terraform {
     required_version = ">= 1.6.0"
   }
   ```

3. **Use Terragrunt Generate Blocks**: In the Terragrunt configuration, use `generate` blocks to create provider configuration files:

   ```hcl
   # In terragrunt.hcl
   generate "provider_k8s" {
     path      = "kubernetes_provider_override.tf"
     if_exists = "overwrite_terragrunt"
     contents = <<EOF
   provider "kubernetes" {
     host                   = var.kubernetes_host
     client_certificate     = base64decode(var.kubernetes_client_certificate)
     client_key             = base64decode(var.kubernetes_client_key)
     cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
   }
   EOF
   }
   ```

4. **Pass Provider Configuration as Variables**: For modules that need provider-specific values (like connection details), pass these as variables rather than embedding them in provider blocks:

   ```hcl
   # In terragrunt.hcl inputs block
   inputs = {
     kubernetes_host                   = dependency.eks.outputs.cluster_endpoint
     kubernetes_cluster_ca_certificate = dependency.eks.outputs.cluster_certificate_authority
   }
   ```

5. **Avoid Duplicate `required_providers` Blocks**: Be careful not to generate provider configuration that conflicts with the root Terragrunt configuration. Use distinct filenames and avoid duplicating the `required_providers` block if it's already defined at the root level.

6. **Use Unique File Names**: When generating provider configuration files, use unique names to avoid conflicts with other generated files:

   ```hcl
   # Good practice
   generate "provider_helm" {
     path = "helm_provider_override.tf"  # Specific, unique name
     # ...
   }
   
   # Avoid
   generate "provider" {  # Generic name may conflict
     path = "provider.tf"
     # ...
   }
   ```

### Dealing with Special Providers

For modules using specialized providers like Kubernetes or Helm:

1. **Documentation**: Clearly document all required provider configuration in the module's README.

2. **Variable Passing**: Accept all necessary provider configuration details as module variables:

   ```hcl
   variable "kubernetes_host" {
     description = "Kubernetes API server host"
     type        = string
   }
   
   variable "kubernetes_client_certificate" {
     description = "Base64 encoded client certificate for Kubernetes authentication"
     type        = string
     default     = ""
   }
   ```

3. **Default Empty Provider Blocks**: If you need placeholder provider blocks for documentation purposes, use empty configurations:

   ```hcl
   /**
    * Provider configuration documentation
    * Note: Actual configuration should be provided by the caller
    */
   
   # Documentation only - will be overridden by caller
   provider "kubernetes" {
     # Configuration will be provided by the caller
   }
   ```

## The `create` Toggle

All resource-creating modules must expose a `create` variable that allows the caller to conditionally disable all resource creation. This is essential for composability -- a composite module or Terragrunt live config can wire up module sources and selectively enable only the pieces it needs.

### Pattern

```hcl
# variables.tf
variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

# main.tf — every resource uses count
resource "aws_ecr_repository" "this" {
  count = var.create ? 1 : 0
  name  = var.name
}

# outputs.tf — conditional to avoid index errors when create = false
output "arn" {
  description = "The ARN of the repository"
  value       = var.create ? aws_ecr_repository.this[0].arn : null
}

output "create" {
  description = "Whether resources were created"
  value       = var.create
}
```

Every resource-creating module implements this pattern. Data-source-only modules do not need it.

## Variable Naming Conventions

Consistent variable naming makes modules predictable for callers:

- **`create`** -- Top-level toggle that gates all resource creation in the module. Always a `bool`, always defaults to `true`.
- **`enable_*`** -- Sub-feature toggles within a module that control optional functionality (e.g., `enable_eks_networking`, `enable_secrets_encryption`, `enable_falcosidekick`). These allow fine-grained control without splitting into separate modules.
- **`null` for optional strings** -- Optional string variables should default to `null` rather than `""`. This lets downstream logic distinguish "not set" from "set to empty" and avoids unexpected empty-string behavior in OpenTofu conditionals.

```hcl
variable "create" {
  type    = bool
  default = true
}

variable "enable_eks_networking" {
  type    = bool
  default = false
}

variable "eks_cluster_name" {
  type    = string
  default = null  # only required when enable_eks_networking = true
}
```

## Cross-Cloud Interface Outputs

Networking modules expose a shared set of output names so that downstream Terragrunt configs and composite modules can consume network information without cloud-specific branching:

| Output               | Description                                    |
|----------------------|------------------------------------------------|
| `network_id`         | The ID of the primary network resource          |
| `network_name`       | The human-readable name of the network          |
| `subnet_ids`         | Map of subnet names to subnet IDs               |
| `kubernetes_subnet_id` | The ID of the subnet designated for Kubernetes |
| `create`             | Whether resources were created                  |

Cloud-specific outputs remain alongside these shared names. For example, the AWS module exposes `vpc_id` and `vpc_cidr_block` alongside the shared names; an Azure module would expose `vnet_id`. The shared names allow cloud-agnostic consumption.

## Composite Module Pattern

Composite modules compose multiple single-purpose modules into a single deployable unit. They do not create resources directly -- they wire together child modules with explicit dependencies and pass configuration through.

### Example: `stack_base`

A composite module composes single-purpose modules into one deployable unit. For example, a base-stack module could wire `networking` + `eks` together (the platform currently wires these as separate Terragrunt units rather than a composite module, but the pattern is the same):

```hcl
module "networking" {
  source = "../aws/networking"
  create = var.create
  # ...
}

module "eks" {
  source     = "../aws/eks"
  create     = var.create
  subnet_ids = module.networking.subnet_ids
  # ...
}
```

Key principles for composite modules:

1. **Source child modules via relative paths** -- use `source = "../aws/networking"` to keep modules in the same repo.
2. **Thread `create` through** -- pass the top-level `create` variable to every child. Sub-features use `var.create && var.enable_*` to combine the top-level gate with feature-specific toggles.
3. **Use child module outputs for wiring** -- never hardcode values that a child module already exposes (e.g., `module.networking.vpc_id`).
4. **Re-export child outputs** -- the composite module's `outputs.tf` should surface the outputs callers need from its children.

## Centralized Versioning with `_versions.hcl`

Module source paths and Helm chart version pins are centralized in `infra/live/aws/_versions.hcl`. Terragrunt live configs access these via `include.base.locals.module_source.<module_name>` and `include.base.locals.helm_versions.<chart_name>`.

```hcl
# _versions.hcl (excerpt)
locals {
  source_base = "${get_repo_root()}/infra/modules"

  module_source = {
    networking   = "${local.source_base}/aws//networking"
    eks          = "${local.source_base}/aws//eks"
    cilium       = "${local.source_base}/cilium"
    # ...
  }
}
```

This approach provides a single place to update module sources when migrating from monorepo-relative paths to an OpenTofu registry with semver tags. Environment-level overrides are supported by defining a local `_versions.hcl` at the environment tier.

## Input Variables

Well-designed module variables follow these principles:

1. **Clear Descriptions**: Every variable should have a clear description of its purpose
2. **Type Constraints**: All variables should have explicit type declarations
3. **Validation Rules**: Use validation blocks to enforce valid input values
4. **Default Values**: Provide sensible defaults where appropriate
5. **Logical Grouping**: Organize related variables together

Example:

```hcl
variable "cluster_name" {
  description = "The name of the EKS cluster"
  type        = string
  validation {
    condition     = length(var.cluster_name) > 0 && length(var.cluster_name) <= 100
    error_message = "Cluster name must be between 1 and 100 characters."
  }
}

variable "tags" {
  description = "A mapping of tags to assign to the resources"
  type        = map(string)
  default     = {}
}
```

## Output Values

Output values should:

1. **Be Comprehensive**: Provide all values needed by consuming modules
2. **Use Clear Names**: Use descriptive names that reflect the resource and attribute
3. **Include Descriptions**: Document the purpose and format of each output

Example:

```hcl
output "id" {
  description = "The ID of the created resource"
  value       = aws_eks_cluster.this.arn
}

output "principal_id" {
  description = "The ARN of the IAM role"
  value       = aws_eks_cluster.this.arnentity[0].principal_id
}
```

## Module Documentation

Each module should include a comprehensive README.md that contains:

1. **Overview**: Brief description of the module's purpose
2. **Requirements**: Prerequisites and dependencies
3. **Resources Created**: List of resources the module creates
4. **Usage Example**: Simple example of how to use the module
5. **Input Variables**: Documented list of all input variables
6. **Output Values**: Documented list of all output values
7. **Notes**: Any important considerations or caveats

## Testing Strategy

Reference Platform modules implement a comprehensive testing approach:

1. **Unit Tests**: Validate individual resource configurations
2. **Integration Tests**: Test interactions between resources
3. **Deployment Tests**: Validate successful deployment in isolated environments
4. **Examples as Tests**: Ensure that example configurations are valid and deployable

See [Testing Strategy](15-testing-strategy.md) for more details.

## Versioning and Releases

Modules follow semantic versioning principles:

1. **Major Version**: Breaking changes to inputs or outputs
2. **Minor Version**: New features, additional outputs (non-breaking)
3. **Patch Version**: Bug fixes and documentation updates

## Common Anti-Patterns

Avoid these common module design mistakes:

1. **Overly Complex Modules**: Trying to handle too many use cases in one module
2. **Hardcoded Values**: Embedding values that should be configurable
3. **Insufficient Documentation**: Lack of clear examples and variable descriptions
4. **Missing Validation**: Not validating input values
5. **Tight Coupling**: Modules that have hidden dependencies on other modules
6. **Duplicate Provider Configurations**: Including provider blocks that conflict with the caller's configuration

## Next Steps

Continue to [Deployment Workflows](14-deployment-workflows.md) to understand how modules are deployed in various environments.
