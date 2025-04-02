# Azure Container Registry - East US (Dev)

## Overview

This directory contains the Terragrunt configuration for deploying and managing Azure Container Registry (ACR) in the East US region for the development environment. The ACR serves as a private registry for storing and managing container images used by AKS and other container workloads.

## Configuration Details

### Purpose

This configuration:
- Creates a secure private registry for storing Docker container images
- Configures appropriate access controls for AKS integration
- Enables secure image distribution for Kubernetes workloads
- Provides a centralized repository for application containers

### Dependencies

This configuration depends on:
- **naming**: Uses standardized resource naming conventions
- **resource_group**: Deploys resources in the specified resource group
- **aks_core**: Integrates with AKS for pull access to container images

### Key Configuration Settings

- **Registry Configuration**:
  - SKU: Standard (supports geo-replication, webhooks, and enhanced throughput)
  - Public Network Access: Enabled (for development environment)
  - AKS Integration: Configured for the AKS cluster's kubelet identity
  - Admin Authentication: Disabled (using Azure AD integration instead)

- **Security Configuration**:
  - Identity-based authentication for AKS via Managed Identity
  - RBAC permissions configured for deployment pipelines
  - Content trust disabled (optional feature for image signing)

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/dev/eastus/container_registry
terragrunt plan
terragrunt apply
```

To login to the container registry after deployment:

```bash
az acr login --name $(terragrunt output name)
```

## Dependencies on this Configuration

The following modules depend on outputs from this configuration:
- aks_core (for image pulls)
- Any CI/CD pipeline configurations for image pushes

## Implementation Notes

For production environments, consider enabling more restrictive network access and content trust settings. The Standard SKU is used for the development environment, but for production, the Premium SKU might be more appropriate for higher throughput requirements and geo-replication capabilities.

AKS has been granted pull access through its kubelet managed identity. For additional security, consider implementing image scan policies and vulnerability management. 