# Infrastructure as Code Approach

## Overview

The VIP Platform adopts a comprehensive Infrastructure as Code (IaC) approach using Terraform and Terragrunt to define, deploy, and manage all cloud resources. This approach ensures consistency, repeatability, and maintainability across all environments and cloud providers.

## Core Technologies

### Terraform

[Terraform](https://www.terraform.io/) is an open-source IaC tool that allows us to define infrastructure resources using a declarative configuration language. The platform uses Terraform for:

- Defining cloud resources using HCL (HashiCorp Configuration Language)
- Managing infrastructure state
- Planning and applying infrastructure changes
- Testing infrastructure configurations
- Validating security and compliance requirements

The minimum required Terraform version for this project is 1.6.0, which provides essential features like:

- Enhanced testing capabilities
- Improved validation functionality
- Enhanced provider abstraction

### Terragrunt

[Terragrunt](https://terragrunt.gruntwork.io/) is a thin wrapper for Terraform that provides additional features to enhance the Terraform experience. We use Terragrunt for:

- Keeping Terraform configurations DRY (Don't Repeat Yourself)
- Managing remote state configuration
- Implementing dependencies between Terraform modules
- Executing commands across multiple Terraform modules
- Providing consistent environment-specific variables

The minimum required Terragrunt version is 0.53.0.

## Project Structure

The VIP Platform follows a well-organized directory structure to manage infrastructure code:

```mermaid
graph TD
    infra[infra/] --> modules[modules/]
    infra --> live[live/]
    infra --> tests[tests/]
    infra --> scripts[scripts/]
    infra --> docs[docs/]
    infra --> makefile[Makefile]
    
    modules --> aws[aws/]
    modules --> azure[azure/]
    modules --> gcp[gcp/]
    modules --> common[common/]
    
    live --> envcommon[_envcommon/]
    live --> cloud_resources[aws/azure/gcp]
    cloud_resources --> env[environments/]
    env --> region[regions/]
    region --> components[components/]
    
    docs --> guides[numbered guides]
    docs --> templates[README-TEMPLATES/]
    docs --> diagrams[diagrams/]
    
    subgraph "Module Categories"
        azure --> base[Base Modules]
        azure --> networking[Networking Modules]
        azure --> compute[Compute Modules]
        azure --> storage[Storage Modules]
        azure --> security[Security Modules]
        azure --> monitoring[Monitoring Modules]
        azure --> cdn[CDN Modules]
    end
    
    subgraph "Azure Modules"
        base --> base_modules[naming, resource_group, client_config]
        networking --> network_modules[networking, private_dns]
        compute --> compute_modules[aks_core, aks_node_pools, aks_identity, container_registry]
        storage --> storage_modules[storage_account, storage_container, storage_roles]
        security --> security_modules[key_vault, identities]
        monitoring --> monitoring_modules[log_analytics, monitor_workspace, prometheus_dcr, managed_grafana]
        cdn --> cdn_modules[frontdoor_profile, frontdoor_endpoint, frontdoor_private_link]
    end
    
    subgraph "Live Environment Structure"
        components --> networking_config[networking/]
        components --> storage_config[storage/]
        components --> compute_config[aks/]
        components --> monitoring_config[monitoring/]
    end
    
    classDef default fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef folder fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef module fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef category fill:#fff8e1,stroke:#ff8f00,stroke-width:2px;
    classDef file fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    
    class infra,modules,live,tests,scripts,docs,aws,azure,gcp,common,envcommon,cloud_resources,env,region,components,diagrams,templates,guides folder;
    class base_modules,network_modules,compute_modules,storage_modules,security_modules,monitoring_modules,cdn_modules module;
    class base,networking,compute,storage,security,monitoring,cdn category;
    class makefile file;
```

### Modules Directory

The `modules` directory contains reusable Terraform modules organized by cloud provider:

- **AWS Modules**: Specific to AWS resources and patterns
- **Azure Modules**: Specific to Azure resources and patterns
- **GCP Modules**: Specific to GCP resources and patterns
- **Common Modules**: Cloud-agnostic patterns and abstractions

Azure modules are organized into logical categories:

1. **Base Modules**:
   - `naming`: Resource naming conventions
   - `resource_group`: Resource group management
   - `client_config`: Current Azure client information

2. **Networking Modules**:
   - `networking`: Virtual networks, subnets, NSGs
   - `private_dns`: Private DNS zones for service integration

3. **Compute Modules**:
   - `aks_core`: AKS cluster creation and management
   - `aks_node_pools`: Additional AKS node pools
   - `aks_identity`: Managed identities for AKS
   - `container_registry`: Azure Container Registry

4. **Storage Modules**:
   - `storage_account`: Azure Storage Account management
   - `storage_container`: Blob containers
   - `storage_roles`: Storage-specific RBAC assignments

5. **Security Modules**:
   - `key_vault`: Secret management
   - `identities`: User-assigned managed identities

6. **Monitoring Modules**:
   - `log_analytics`: Log aggregation and analysis
   - `monitor_workspace`: Metrics storage (Prometheus)
   - `prometheus_dcr`: Prometheus data collection rules
   - `managed_grafana`: Metrics visualization

7. **CDN Modules**:
   - `frontdoor_profile`: CDN profile management
   - `frontdoor_endpoint`: User-facing endpoints
   - `frontdoor_private_link`: Secure backend connections

Each module follows a consistent structure:

```mermaid
graph TD
    module[module-name/] --> main[main.tf]
    module --> variables[variables.tf]
    module --> outputs[outputs.tf]
    module --> readme[README.md]
    module --> optional[optional *.tf files]
    
    classDef default fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef folder fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef file fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    
    class module folder;
    class main,variables,outputs,readme,optional file;
```

### Tests Directory

The `tests` directory contains all test configurations for validating infrastructure modules. Tests are organized to mirror the module structure:

```mermaid
graph TD
    tests[tests/] --> modules_tests[modules/]
    
    modules_tests --> aws_tests[aws/]
    modules_tests --> azure_tests[azure/]
    modules_tests --> gcp_tests[gcp/]
    modules_tests --> common_tests[common/]
    
    azure_tests --> networking_tests[networking/]
    azure_tests --> storage_tests[storage_account/]
    azure_tests --> other_tests[...]
    
    classDef default fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef folder fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    
    class tests,modules_tests,aws_tests,azure_tests,gcp_tests,common_tests,networking_tests,storage_tests,other_tests folder;
```

The tests directory contains:
- Unit tests for individual modules
- Integration tests for combinations of modules
- Compliance tests for security and best practices

> **Important**: Tests must be placed in the `tests` directory, not within module directories, to maintain separation between implementation and test code.

### Live Directory

The `live` directory contains the actual infrastructure configurations for different environments and regions:

- **_envcommon**: Common configurations shared across environments
- **Global**: Global resources not tied to specific regions
- **AWS/Azure/GCP**: Cloud-specific resources organized by environment and region

Each environment/region directory contains Terragrunt configurations for different infrastructure components:

```mermaid
graph TD
    live_dir[live/azure/dev/westus/] --> networking_dir[networking/]
    live_dir --> storage_dir[storage/]
    live_dir --> key_vault_dir[key_vault/]
    live_dir --> aks_core_dir[aks_core/]
    live_dir --> common_file[common.hcl]
    
    networking_dir --> networking_config[terragrunt.hcl]
    storage_dir --> storage_config[terragrunt.hcl]
    key_vault_dir --> key_vault_config[terragrunt.hcl]
    aks_core_dir --> aks_core_config[terragrunt.hcl]
    
    classDef default fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef folder fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef file fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    
    class live_dir,networking_dir,storage_dir,key_vault_dir,aks_core_dir folder;
    class networking_config,storage_config,key_vault_config,aks_core_config,common_file file;
```

## Development Workflow

### Module Development

1. **Create Module Template**: Start with a standardized module template
2. **Define Interfaces**: Clearly define input variables and outputs
3. **Write Tests**: Create tests to validate module functionality
4. **Implement Module**: Develop the module implementation
5. **Test and Validate**: Run tests to ensure module works as expected
6. **Document**: Create comprehensive README documentation

### Infrastructure Deployment

1. **Plan Changes**: Review proposed changes with `terragrunt plan`
2. **Apply Changes**: Apply changes with `terragrunt apply`
3. **Validate Deployment**: Verify resources are created correctly
4. **Run Tests**: Execute automated tests to validate infrastructure

## Module Dependencies

Terragrunt manages dependencies between modules to ensure proper deployment order. Below is an example of a typical dependency graph for Azure resources:

```mermaid
graph TD
    naming[naming] --> resource_group[resource_group]
    resource_group --> networking[networking]
    resource_group --> key_vault[key_vault]
    resource_group --> aks_identity[aks_identity]
    resource_group --> storage_account[storage_account]
    resource_group --> container_registry[container_registry]
    resource_group --> log_analytics[log_analytics]
    resource_group --> monitor_workspace[monitor_workspace]
    
    networking --> aks_core[aks_core]
    networking --> storage_account
    networking --> key_vault
    networking --> private_dns[private_dns]
    networking --> frontdoor_private_link[frontdoor_private_link]
    
    aks_identity --> aks_core
    aks_core --> aks_node_pools[aks_node_pools]
    
    client_config[client_config] --> key_vault
    client_config --> storage_roles[storage_roles]
    
    storage_account --> storage_container[storage_container]
    storage_account --> storage_roles
    
    monitor_workspace --> prometheus_dcr[prometheus_dcr]
    monitor_workspace --> managed_grafana[managed_grafana]
    
    log_analytics --> aks_core
    
    prometheus_dcr --> aks_core
    
    frontdoor_profile[frontdoor_profile] --> frontdoor_endpoint[frontdoor_endpoint]
    frontdoor_profile --> frontdoor_private_link
    
    classDef default fill:#f9f9f9,stroke:#333,stroke-width:1px;
    classDef base fill:#e1f5fe,stroke:#01579b,stroke-width:2px;
    classDef network fill:#e8f5e9,stroke:#2e7d32,stroke-width:2px;
    classDef compute fill:#fff8e1,stroke:#ff8f00,stroke-width:2px;
    classDef storage fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px;
    classDef security fill:#ffebee,stroke:#c62828,stroke-width:2px;
    classDef monitoring fill:#e0f7fa,stroke:#006064,stroke-width:2px;
    classDef cdn fill:#fff3e0,stroke:#e65100,stroke-width:2px;
    
    class naming,resource_group,client_config base;
    class networking,private_dns network;
    class aks_core,aks_node_pools,container_registry compute;
    class storage_account,storage_container,storage_roles storage;
    class key_vault,aks_identity security;
    class log_analytics,monitor_workspace,prometheus_dcr,managed_grafana monitoring;
    class frontdoor_profile,frontdoor_endpoint,frontdoor_private_link cdn;
```

This dependency graph ensures that resources are created in the correct order, with foundational resources like resource groups created first, followed by networking resources, and finally application-specific resources.

## Example: Terragrunt Configuration

A typical Terragrunt configuration file (`terragrunt.hcl`) looks like:

```hcl
include "root" {
  path = find_in_parent_folders()
}

include "env" {
  path = find_in_parent_folders("env.hcl")
}

include "region" {
  path = find_in_parent_folders("region.hcl")
}

terraform {
  source = "${get_path_to_repo_root()}/infra/modules/azure/networking"
}

dependency "resource_group" {
  config_path = "../resource_group"
  mock_outputs = {
    resource_group_name = "mock-rg"
  }
}

inputs = {
  resource_group_name = dependency.resource_group.outputs.resource_group_name
  address_space       = ["10.0.0.0/16"]
  
  subnets = {
    "az1-node-subnet" = {
      address_prefix = "10.0.0.0/24"
      security_rules = ["allow_ssh", "allow_http"]
    }
    "az2-node-subnet" = {
      address_prefix = "10.0.1.0/24"
      security_rules = ["allow_ssh", "allow_http"]
    }
  }
}
```

## Example: Module Structure

A typical module implementation looks like:

```hcl
# main.tf

locals {
  vnet_name = var.name != null ? var.name : "vnet-${var.environment}-${var.region_abbv}"
  tags = merge(var.tags, {
    ManagedBy = "Terraform"
    Module    = "networking"
  })
}

resource "azurerm_virtual_network" "vnet" {
  name                = local.vnet_name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = var.address_space
  
  dynamic "ddos_protection_plan" {
    for_each = var.ddos_protection_plan_id != null ? [1] : []
    content {
      id     = var.ddos_protection_plan_id
      enable = true
    }
  }
  
  tags = local.tags
}

resource "azurerm_subnet" "subnet" {
  for_each = var.subnets
  
  name                 = each.key
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.vnet.name
  address_prefixes     = [each.value.address_prefix]
  service_endpoints    = try(each.value.service_endpoints, [])
  
  dynamic "delegation" {
    for_each = try(each.value.delegation, null) != null ? [1] : []
    content {
      name = each.value.delegation.name
      service_delegation {
        name    = each.value.delegation.service_name
        actions = each.value.delegation.actions
      }
    }
  }
}

resource "azurerm_network_security_group" "nsg" {
  for_each = var.subnets
  
  name                = "${each.key}-nsg"
  location            = var.location
  resource_group_name = var.resource_group_name
  
  dynamic "security_rule" {
    for_each = try(flatten([
      for rule_name in each.value.security_rules : [
        var.security_rules[rule_name]
      ]
    ]), [])
    
    content {
      name                       = security_rule.value.name
      priority                   = security_rule.value.priority
      direction                  = security_rule.value.direction
      access                     = security_rule.value.access
      protocol                   = security_rule.value.protocol
      source_port_range          = try(security_rule.value.source_port_range, "*")
      destination_port_range     = try(security_rule.value.destination_port_range, "*")
      source_address_prefix      = try(security_rule.value.source_address_prefix, "*")
      destination_address_prefix = try(security_rule.value.destination_address_prefix, "*")
    }
  }
  
  tags = local.tags
}

resource "azurerm_subnet_network_security_group_association" "nsg_association" {
  for_each = var.subnets
  
  subnet_id                 = azurerm_subnet.subnet[each.key].id
  network_security_group_id = azurerm_network_security_group.nsg[each.key].id
}

# variables.tf

variable "name" {
  description = "The name of the virtual network (generated if not provided)"
  type        = string
  default     = null
}

variable "resource_group_name" {
  description = "The name of the resource group"
  type        = string
  
  validation {
    condition     = length(var.resource_group_name) >= 3 && length(var.resource_group_name) <= 63
    error_message = "Resource group name must be between 3 and 63 characters."
  }
}

variable "location" {
  description = "The Azure region where resources will be created"
  type        = string
}

variable "address_space" {
  description = "The address spaces for the virtual network"
  type        = list(string)
}

variable "subnets" {
  description = "Map of subnet objects to create"
  type = map(object({
    address_prefix    = string
    security_rules    = optional(list(string), [])
    service_endpoints = optional(list(string), [])
    delegation = optional(object({
      name         = string
      service_name = string
      actions      = list(string)
    }))
  }))
  default = {}
}

variable "security_rules" {
  description = "Map of security rules that can be referenced by subnets"
  type = map(object({
    name                       = string
    priority                   = number
    direction                  = string
    access                     = string
    protocol                   = string
    source_port_range          = optional(string)
    destination_port_range     = optional(string)
    source_address_prefix      = optional(string)
    destination_address_prefix = optional(string)
  }))
  default = {}
}

variable "ddos_protection_plan_id" {
  description = "The ID of the DDoS protection plan to associate with the virtual network"
  type        = string
  default     = null
}

variable "environment" {
  description = "Environment name (dev, test, staging, prod)"
  type        = string
  default     = "dev"
}

variable "region_abbv" {
  description = "Abbreviation for Azure region (used in resource naming)"
  type        = string
  default     = "eus"
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# outputs.tf

output "id" {
  description = "The ID of the virtual network"
  value       = azurerm_virtual_network.vnet.id
}

output "name" {
  description = "The name of the virtual network"
  value       = azurerm_virtual_network.vnet.name
}

output "subnet_ids" {
  description = "Map of subnet names to subnet IDs"
  value = {
    for k, v in azurerm_subnet.subnet : k => v.id
  }
}

output "nsg_ids" {
  description = "Map of subnet names to NSG IDs"
  value = {
    for k, v in azurerm_network_security_group.nsg : k => v.id
  }
}
```

## Testing Approach

The VIP Platform uses Terraform's built-in testing framework to validate module functionality:

```hcl
# Example test file: networking/tests/basic.tftest.hcl

run "prepare_workspace" {
  module {
    source = "../"
  }
}

variables {
  vnet_name           = "test-vnet"
  resource_group_name = "test-rg"
  location            = "eastus"
  address_space       = ["10.0.0.0/16"]
  
  subnets = {
    "subnet1" = {
      address_prefix = "10.0.0.0/24"
      security_rules = ["allow_ssh"]
    }
  }
}

run "verify_vnet_creation" {
  command = apply
  
  assert {
    condition     = azurerm_virtual_network.vnet.name == "test-vnet"
    error_message = "VNet name did not match expected value"
  }
  
  assert {
    condition     = length(azurerm_subnet.subnet) == 1
    error_message = "Expected 1 subnet to be created"
  }
}

run "verify_subnet_security" {
  command = apply
  
  assert {
    condition     = length(azurerm_network_security_group.nsg) == 1
    error_message = "Expected 1 NSG to be created"
  }
  
  assert {
    condition     = length(azurerm_subnet_network_security_group_association.nsg_association) == 1
    error_message = "Expected 1 NSG association to be created"
  }
}
```

### Comprehensive Testing Strategy

Our testing approach includes several levels of validation:

1. **Unit Tests**: Validate individual modules in isolation
   - Verify resource creation
   - Test input validation rules
   - Confirm outputs match expectations

2. **Integration Tests**: Test combinations of modules working together
   - Verify dependencies are correctly managed
   - Test end-to-end flows like networking to compute

3. **Compliance Tests**: Ensure security and best practices
   - Validate network security rules
   - Check for required tags
   - Verify encryption settings

4. **Regression Tests**: Prevent reintroduction of fixed issues
   - Maintain tests for all previously identified bugs
   - Include edge cases and boundary conditions

Tests are run using the project's Makefile with the following commands:

```bash
# Run all tests
make test

# Run tests for a specific module
make test-module MODULE=azure/networking

# Run tests with verbose output
make test-verbose
```

The Makefile provides a standardized and consistent way to run tests across the codebase and is the preferred method for both local testing and CI/CD pipelines.

## Best Practices

1. **Module Design**:
   - Focus on single responsibility
   - Provide sensible defaults
   - Validate inputs
   - Include comprehensive documentation

2. **Terragrunt Usage**:
   - Keep DRY with common includes
   - Use dependencies for resource references
   - Use mock outputs for testing
   - Maintain consistent directory structure

3. **State Management**:
   - Use remote state with locking
   - Isolate state by environment and component
   - Back up state files regularly
   - Monitor for state drift

4. **Secret Management**:
   - Never store secrets in version control
   - Use Azure Key Vault for secure storage
   - Use environment variables for sensitive inputs
   - Leverage managed identities where possible

5. **Testing**:
   - Write tests for all modules
   - Use both unit and integration tests
   - Include negative test cases
   - Verify resource properties and security configurations

## Next Steps

Continue to [Multi-Cloud Strategy](04-multi-cloud-strategy.md) to understand how the VIP Platform implements a consistent approach across different cloud providers. 