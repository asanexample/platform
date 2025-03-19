# Infrastructure Documentation

Welcome to the infrastructure documentation for our multi-cloud platform. This directory contains comprehensive documentation covering various aspects of our infrastructure design, deployment, and management.

## Documentation Index

| Document | Description |
|----------|-------------|
| [Getting Started](getting-started.md) | Guide for setting up local development environment |
| [Architecture Overview](architecture.md) | High-level architecture and design decisions |
| [AKS Configuration](aks-configuration.md) | AKS cluster setup and configurations |
| [Cilium Integration](cilium-integration.md) | Guide for Cilium CNI integration with AKS and network configuration |
| [Cilium Installation](cilium-installation.md) | Detailed instructions for installing and configuring Cilium CNI |
| [CIDR Allocation](cidr-allocation.md) | Strategy for IP address allocation across cloud providers, environments, and regions |
| [Multi-Region Deployment](multi-region-deployment.md) | Guide for deploying infrastructure across multiple regions for high availability and disaster recovery |
| [Network CIDR Allocations](network-cidr-allocations.md) | Detailed breakdown of network CIDR allocations for each component |
| [Network Topology](network-topology.md) | Overview of the network architecture, including VNets, subnets, and connectivity |
| [Naming Conventions](naming-conventions.md) | Resource naming standards |
| [Networking](networking.md) | Network architecture and configuration |
| [Security](security.md) | Security practices and configurations |
| [CI/CD Pipeline](cicd.md) | Continuous integration and deployment workflows |
| [Monitoring](monitoring.md) | Monitoring and alerting configurations |
| [Cost Management](cost-management.md) | Guidelines for managing cloud costs |
| [Disaster Recovery](disaster-recovery.md) | Disaster recovery strategies and procedures |

## Quick Start

If you're new to this documentation, we recommend starting with:

1. [Getting Started](getting-started.md) - Initial setup requirements
2. [Architecture Overview](architecture.md) - Understand the design
3. [AKS Configuration](aks-configuration.md) - Learn AKS setup
4. [Cilium Integration](cilium-integration.md) - Understand CNI approach
5. [Networking](networking.md) - Network configuration

## Infrastructure Components

The platform infrastructure consists of the following key components:

- **Core Infrastructure**
  - Resource Groups
  - Virtual Networks
  - Subnets
  - Network Security Groups
  - Private DNS Zones

- **Compute Resources**
  - AKS Clusters
    - Node Pools
    - Pod Identity
    - CNI (Cilium)
  - Azure Container Registry
  - Virtual Machines (jumpboxes/bastion hosts)

- **Storage**
  - Azure Storage Accounts
  - Azure Managed Disks
  - Azure File Shares

- **Identity and Access**
  - Azure Active Directory
  - Managed Identities
  - RBAC Assignments

- **Networking**
  - Load Balancers
  - Application Gateway
  - Network Security Groups
  - Private Endpoints
  - Virtual Network Peering

- **Monitoring and Logging**
  - Azure Monitor
  - Log Analytics Workspace
  - Application Insights

## Infrastructure as Code

All infrastructure is managed using:

- **Terraform**: For defining infrastructure components
- **Terragrunt**: For managing Terraform configurations across environments
- **Azure DevOps**: For CI/CD pipelines to deploy infrastructure

## Common Tasks

Here are quick links to documentation for common infrastructure tasks:

- [Adding a new AKS node pool](aks-configuration.md#aks-node-pools-module)
- [Configuring network security](network-topology.md#network-security)
- [Setting up multi-region connectivity](multi-region-deployment.md#inter-region-connectivity)
- [Implementing identity management](security.md#identity-and-access-management)
- [Configuring Cilium](cilium-installation.md)
- [Setting up monitoring](monitoring.md)
- [Applying security patches](security.md#patching)

## Contributing to Documentation

When updating or adding documentation:

1. Follow the established formatting and style
2. Update the table of contents as needed
3. Keep diagrams up to date with actual infrastructure
4. Cross-reference related documentation
5. Ensure all CIDR allocations are properly recorded

## Additional Resources

- [Root README](../../README.md) - The main project README
- [NAMING_CONVENTIONS.md](../../NAMING_CONVENTIONS.md) - Global naming convention documentation
- [IMPLEMENTATION.md](../../IMPLEMENTATION.md) - Implementation details and design decisions

## Terraform Standards

This infrastructure uses:
- Terraform >= 1.0.0
- Terragrunt >= 0.36.0
- Terraform Registry modules where possible
- Custom modules for organization-specific needs

For detailed guidelines on Terraform best practices, see [Terraform Standards](terraform-standards.md). 