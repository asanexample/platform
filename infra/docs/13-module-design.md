# Module Design

## Overview

This document outlines the principles and best practices for designing Terraform modules within the VIP Platform. Properly structured modules are essential for maintainability, reusability, and consistency across infrastructure deployments.

## Design Principles

VIP Platform modules follow these core design principles:

1. **Single Responsibility**: Each module should have a clear, focused purpose
2. **High Cohesion**: Related resources should be grouped together
3. **Low Coupling**: Minimize dependencies between modules
4. **Clear Interfaces**: Well-defined inputs and outputs
5. **Sensible Defaults**: Provide reasonable default values where appropriate
6. **Complete Documentation**: Comprehensive README with examples and usage guidelines

## Module Structure

All modules follow a consistent structure:

```
modules/azure/example_module/
├── main.tf           # Primary resources
├── variables.tf      # Input variables
├── outputs.tf        # Output values
├── versions.tf       # Required Terraform and provider versions
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
       azurerm = {
         source  = "hashicorp/azurerm"
         version = "~> 4.25.0"
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
     kubernetes_host = dependency.aks_core.outputs.host
     kubernetes_client_certificate = dependency.aks_core.outputs.client_certificate
     kubernetes_client_key = dependency.aks_core.outputs.client_key
     kubernetes_cluster_ca_certificate = dependency.aks_core.outputs.cluster_ca_certificate
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

## Input Variables

Well-designed module variables follow these principles:

1. **Clear Descriptions**: Every variable should have a clear description of its purpose
2. **Type Constraints**: All variables should have explicit type declarations
3. **Validation Rules**: Use validation blocks to enforce valid input values
4. **Default Values**: Provide sensible defaults where appropriate
5. **Logical Grouping**: Organize related variables together

Example:

```hcl
variable "resource_group_name" {
  description = "The name of the resource group in which to create the resources"
  type        = string
  validation {
    condition     = length(var.resource_group_name) > 0 && length(var.resource_group_name) <= 90
    error_message = "Resource group name must be between 1 and 90 characters."
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
  value       = azurerm_resource.example.id
}

output "principal_id" {
  description = "The Principal ID of the managed identity associated with the resource"
  value       = azurerm_resource.example.identity[0].principal_id
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

VIP Platform modules implement a comprehensive testing approach:

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