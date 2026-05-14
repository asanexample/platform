# Azure Container Registry - West US (Ops)

## Overview

This directory contains the Terragrunt configuration for deploying and managing Azure Container Registry (ACR) in the West US region for the operations environment. The ACR serves as a private registry for storing and managing container images used by AKS and other operational container workloads.

## Configuration Details

### Purpose

This configuration:
- Creates a secure private registry for storing Docker container images for operations workloads
- Configures appropriate access controls for AKS integration
- Enables secure image distribution for operational Kubernetes workloads
- Provides a centralized repository for operations container images
- Implements higher security standards appropriate for operational environments

### Dependencies

This configuration depends on:
- **naming**: Uses standardized resource naming conventions
- **resource_group**: Deploys resources in the specified resource group
- **aks_core**: Integrates with AKS for pull access to container images

### Key Configuration Settings

- **Registry Configuration**:
  - SKU: Premium (supports enhanced throughput, geo-replication, and content trust)
  - Public Network Access: Limited (restricted network access policies)
  - AKS Integration: Configured for the AKS cluster's kubelet identity
  - Admin Authentication: Disabled (using Azure AD integration instead)

- **Security Configuration**:
  - Identity-based authentication for AKS via Managed Identity
  - RBAC permissions configured for deployment pipelines
  - Content trust enabled for image signing
  - Private Link connectivity (in production)

## Usage

To plan and apply this configuration:

```bash
cd infra/live/azure/ops/westus/container_registry
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
- CI/CD pipeline configurations for image pushes
- Operational workloads that require container images

## Implementation Notes

The operations environment ACR uses the Premium SKU to provide enhanced security features, higher throughput, and geo-replication capabilities to support operational workloads. 

Security considerations implemented in this configuration include:
- Limited public network access
- RBAC-based access control
- Integration with AKS through managed identities
- Support for private network connectivity

For complete security in production, consider implementing:
1. Private Link connectivity to completely isolate the registry from the public internet
2. Image scanning policies to detect vulnerabilities
3. Content trust (Docker Notary) to enforce signed images
4. Geo-replication for disaster recovery and performance
5. Custom image retention policies to manage registry size 