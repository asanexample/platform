# Available Modules

## Overview

The VIP Platform includes a set of reusable Terraform modules for deploying infrastructure across multiple cloud providers. This document provides an overview of the available modules, their capabilities, and usage guidelines.

*This document is under development. The full content will be available soon.*

## Module Categories

The modules are organized into the following categories:

1. **AWS Modules**: For AWS-specific resources
2. **Azure Modules**: For Azure-specific resources
3. **GCP Modules**: For GCP-specific resources
4. **Common Modules**: For cloud-agnostic abstractions

## Azure Modules

The following Azure modules are available:

### Networking Module

- **Path**: `modules/azure/networking`
- **Purpose**: Create and configure Azure virtual networks, subnets, and network security groups
- **Key Features**:
  - Multi-AZ subnet configuration
  - Security group integration
  - Service endpoint configuration
  - DNS customization

### Storage Account Module

- **Path**: `modules/azure/storage_account`
- **Purpose**: Create and configure Azure storage accounts
- **Key Features**:
  - Network rules configuration
  - Lifecycle management
  - Encryption settings
  - Access tier configuration

### Key Vault Module

- **Path**: `modules/azure/key_vault`
- **Purpose**: Create and configure Azure Key Vault resources
- **Key Features**:
  - RBAC and access policy support
  - Network rule configuration
  - Purge protection
  - Soft delete configuration

### AKS Core Module

- **Path**: `modules/azure/aks_core`
- **Purpose**: Deploy Azure Kubernetes Service (AKS) clusters
- **Key Features**:
  - Multi-AZ configuration
  - Network integration
  - Security settings
  - Monitoring configuration

### AKS Identity Module

- **Path**: `modules/azure/aks_identity`
- **Purpose**: Configure identity for AKS clusters
- **Key Features**:
  - Managed identity integration
  - Workload identity federation
  - RBAC configuration
  - Service principal management

### AKS Node Pools Module

- **Path**: `modules/azure/aks_node_pools`
- **Purpose**: Manage AKS node pools
- **Key Features**:
  - Multi-AZ deployment
  - Auto-scaling configuration
  - Node taints and labels
  - Spot instance support

### More Azure Modules

*Additional Azure modules will be documented in a future update.*

## AWS Modules

*AWS modules will be documented in a future update.*

## GCP Modules

*GCP modules will be documented in a future update.*

## Common Modules

*Common modules will be documented in a future update.*

## Module Usage Guidelines

*Documentation on module usage guidelines will be provided in a future update.*

## Next Steps

Continue to [Troubleshooting Guide](18-troubleshooting.md) to understand how to diagnose and resolve common issues. 