# Azure AKS Core Module - East US (Dev)

## Overview
This module provisions and configures the core Azure Kubernetes Service (AKS) cluster in the East US region for the development environment. It sets up a production-ready Kubernetes platform with appropriate security and networking configurations.

## Configuration Details

### Purpose
Creates a production-ready AKS cluster that:
- Provides a secure platform for container workloads
- Follows Azure and Kubernetes best practices
- Implements private networking and enhanced security
- Enables proper monitoring and management

### Dependencies
- **naming**: Uses standardized resource names
- **resource_group**: Deploys resources in the specified resource group
- **networking**: Uses network configuration for cluster networking
- **aks_identity**: Uses managed identity for the AKS cluster

### Key Configuration Settings
- **Cluster Configuration**:
  - Kubernetes Version: 1.27.7 (Stable channel)
  - Private Cluster: Enabled
  - Network Plugin: Azure CNI
  - Network Policy: Azure (configured for eventual Cilium deployment)
  - Outbound Type: User-defined routing
- **System Node Pool**:
  - VM Size: Standard_D4s_v3
  - Node Count: 3-5 (Auto-scaling enabled)
  - Zone Redundancy: Enabled across 3 availability zones
  - OS Disk Type: Ephemeral
  - OS Disk Size: 128 GB
  - Max Pods per Node: 30
- **Security Features**:
  - Workload Identity: Enabled
  - OIDC Issuer: Enabled
  - RBAC: Enabled with Azure AD integration
  - Local accounts: Disabled
  - Microsoft Defender for Containers: Enabled
- **Monitoring**:
  - Azure Monitor: Enabled
  - Log Analytics Integration: Enabled with dedicated workspace

## Implementation Details
The AKS Core module uses the [Azure AKS Module](/infra/modules/azure/aks) to create a standardized Kubernetes environment with:

- System node pool configurations optimized for Kubernetes system components
- Identity configuration using managed identities for enhanced security
- Network integration with the VNet created by the networking module
- Support for workload identity for pod-based authentication
- Maintenance window configured for off-peak hours

## Multi-AZ Design
The cluster is designed with a multi-availability zone architecture:
- System nodes distributed across 3 availability zones
- Dedicated subnet for each availability zone to increase fault tolerance
- Load balancer configured for zone-redundant operation

## Post-Deployment Configuration
After deployment, additional components are installed through Kubernetes manifests and Helm charts:
- Cilium CNI (replaces Azure CNI for networking)
- Cert-Manager for certificate management
- External-DNS for DNS automation
- Ingress controllers for traffic management

## Usage Example

To apply this module:
```bash
cd aks_core
terragrunt apply
```

To view cluster credentials after deployment:
```bash
cd aks_core
terragrunt output kube_config_raw > ~/.kube/config
```

## Dependencies on this Module
The following modules depend on outputs from this module:
- aks_node_pools 

## Maintenance and Updates
The AKS cluster is configured with automatic upgrades through the "stable" channel. This ensures the cluster receives security patches and minor version updates automatically, while major version upgrades are handled manually.

Maintenance windows are configured for Sundays between 00:00-03:00 UTC to minimize disruption to workloads. 