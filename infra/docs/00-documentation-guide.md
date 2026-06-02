# Platform Documentation Guide

This directory contains the infrastructure reference documentation. It
covers architecture, design patterns, conventions, and operational guides
for the platform — AWS-first today, multi-cloud by design (Azure/GCP planned).

For ADRs, runbooks, and onboarding, see [`docs/`](../../docs/).

## Documentation Structure

1. **Project Overview**
   - [Introduction](01-introduction.md)
   - [Architecture Overview](02-architecture-overview.md)

2. **Core Concepts**
   - [Infrastructure as Code Approach](03-infrastructure-as-code.md)
   - [Multi-Cloud Strategy](04-multi-cloud-strategy.md)
   - [Environment Management](05-environment-management.md)

3. **Network Architecture**
   - [CIDR Allocation Strategy](06-cidr-allocation.md)
   - [Network Topology](07-network-topology.md)
   - [Kubernetes Network Design](08-kubernetes-network-design.md)

4. **Security and Compliance**
   - [Security Architecture](09-security-architecture.md)
   - [Compliance Framework](10-compliance-framework.md)

5. **Implementation Patterns**
   - [Naming Conventions](11-naming-conventions.md)
   - [Tagging Strategy](12-tagging-strategy.md)
   - [Module Design Principles](13-module-design.md)

6. **Operations**
   - [Deployment Workflows](14-deployment-workflows.md)
   - [Testing Strategy](15-testing-strategy.md)
   - [Disaster Recovery](16-disaster-recovery.md)

7. **Reference**
   - [Available Modules](17-available-modules.md)
   - [Troubleshooting Guide](18-troubleshooting.md)
   - [Cost Management Strategy](19-cost-management.md)
   - [Region Scaffolding](20-region-scaffolding.md)

## How to Use This Documentation

Start with the [Introduction](01-introduction.md) and
[Architecture Overview](02-architecture-overview.md) for the high-level
picture. Then explore by role:

- **Infrastructure engineers**: [IaC Approach](03-infrastructure-as-code.md),
  [Naming Conventions](11-naming-conventions.md),
  [Module Design](13-module-design.md)
- **Network engineers**: [CIDR Allocation](06-cidr-allocation.md),
  [Network Topology](07-network-topology.md),
  [Kubernetes Network Design](08-kubernetes-network-design.md)
- **Security / compliance**: [Security Architecture](09-security-architecture.md),
  [Compliance Framework](10-compliance-framework.md)
- **Operations / finance**: [Cost Management](19-cost-management.md),
  [Tagging Strategy](12-tagging-strategy.md),
  [Environment Management](05-environment-management.md)

## Related Documentation

- [`docs/`](../../docs/) -- ADRs, runbooks, onboarding, troubleshooting
- [`docs/architecture/config-hierarchy.md`](../../docs/architecture/config-hierarchy.md) --
  Terragrunt configuration hierarchy deep dive
- [`CLAUDE.md`](../../CLAUDE.md) -- deployment ordering, key commands,
  architecture decisions
