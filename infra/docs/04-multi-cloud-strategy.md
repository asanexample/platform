# Multi-Cloud Strategy

## Overview

The VIP Platform is designed from the ground up to support multiple cloud providers (AWS, Azure, and GCP) with consistent patterns and abstractions. This document outlines the multi-cloud strategy, including design principles, implementation patterns, and operational considerations.

**Current Implementation Status**: Azure is the primary implementation, with AWS and GCP networking modules now implemented and live config hierarchies in place for all three clouds.

## Design Principles

The multi-cloud strategy is guided by the following principles:

1. **Consistent Abstractions**: Common patterns and interfaces across cloud providers.
2. **Cloud-Native When Appropriate**: Leveraging cloud-native services where they provide significant advantages.
3. **Avoid Lowest Common Denominator**: Not limiting functionality to only what's available in all clouds.
4. **Modularity**: Cloud-specific implementations behind common interfaces.
5. **Escape Hatches**: Ability to access cloud-specific features when needed.

## Implementation Approach

The multi-cloud implementation follows a phased approach:

1. **Phase 1**: Azure implementation (complete -- full module suite)
2. **Phase 2**: AWS networking implementation (complete)
3. **Phase 3**: GCP networking implementation (complete)
4. **Phase 4**: Cross-cloud integration (in progress -- shared output interface established)

### Module Structure

The Terraform modules are organized to support the multi-cloud strategy:

- **Common Modules**: Cloud-agnostic abstractions (planned)
- **AWS Modules**: AWS-specific implementations (networking implemented)
- **Azure Modules**: Azure-specific implementations (complete)
- **GCP Modules**: GCP-specific implementations (networking implemented)

Currently implemented modules by cloud:
- **Azure**: Networking, storage, AKS clusters and node pools, Key Vault, resource groups, naming, monitoring, CDN, identities, composite stacks (`stack_base`)
- **AWS**: Networking (VPC, subnets, NAT gateways, route tables, EKS security groups), naming
- **GCP**: Networking (VPC, subnets, Cloud Router, Cloud NAT), naming
- **Cloud-agnostic**: vCluster (virtual Kubernetes clusters), policy (Kyverno placeholder)

### Cross-Cloud Interface Pattern

All networking modules across clouds expose a shared set of output names, enabling Terragrunt live configs to consume any cloud's networking module uniformly:

| Output | Azure | AWS | GCP |
|--------|-------|-----|-----|
| `network_id` | VNet ID | VPC ID | VPC Network ID |
| `network_name` | VNet name | VPC name | VPC Network name |
| `subnet_ids` | Map of subnet names to IDs | Map of subnet names to IDs | Map of subnet names to IDs |
| `kubernetes_subnet_id` | AKS subnet ID | First EKS subnet ID | GKE subnet ID |
| `create` | Whether resources were created | Whether resources were created | Whether resources were created |

Each cloud module also exposes cloud-specific outputs (e.g., AWS: `vpc_cidr_block`, `nat_gateway_ids`; GCP: `vpc_self_link`, `cloud_nat_id`) alongside the shared interface.

### Unified Naming Module Contract

In addition to the networking interface, all three cloud naming modules (`azure/naming`, `aws/naming`, `gcp/naming`) share a unified input contract:

| Input | Type | Description |
|-------|------|-------------|
| `workload` | `string` | Workload identifier (e.g., `platform`, `data`, `hipaa`) |
| `environment` | `string` | Environment name (e.g., `dev`, `prod`, `ops`) |
| `region_abbv` | `string` | Cloud-specific abbreviated region (e.g., `eus`, `use1`, `usc1`) |

Each module generates cloud-appropriate names following the CAF-aligned pattern `{type}-{workload}-{env}-{region}`, with cloud-specific accommodations for character limits, casing rules, and globally-unique resources. This shared contract means Terragrunt live configs can pass the same `workload`, `environment`, and `region_abbv` locals to any cloud's naming module without modification.

### Terragrunt Configuration

The Terragrunt configuration follows a consistent pattern across cloud providers:

- Root `terragrunt.hcl` with provider configurations
- Cloud-level `_base.hcl` for shared configuration and safety validations
- Cloud-level `_versions.hcl` for centralized module source paths and version pins
- Cloud-level `common.hcl` for cloud-wide defaults
- Environment-specific settings in `env.hcl` files
- Region-specific settings in `region.hcl` and `network.hcl` files
- Common configuration patterns in `_envcommon` directory

Live config hierarchies exist for all three clouds:
- `infra/live/azure/` -- full environment structure (dev, ops, etc.)
- `infra/live/aws/` -- ops environment with `_base.hcl` and `common.hcl`
- `infra/live/gcp/` -- ops environment with `_base.hcl` and `common.hcl`

## Cloud Feature Parity Matrix

The following matrix tracks implementation status across cloud providers:

| Feature | Azure | AWS | GCP |
|---------|-------|-----|-----|
| Networking | Implemented | Implemented | Implemented |
| Naming | Implemented | Implemented | Implemented |
| Live config hierarchy | Implemented | Implemented | Implemented |
| `_base.hcl` shared config | Implemented | Implemented | Implemented |
| Storage | Implemented | Planned | Planned |
| Kubernetes | Implemented | Planned | Planned |
| Identity | Implemented | Planned | Planned |
| Key Management | Implemented | Planned | Planned |
| Monitoring | Implemented | Planned | Planned |
| CDN | Implemented | Planned | Planned |
| Composite stacks | Implemented (`stack_base`) | Planned | Planned |
| vCluster | Cloud-agnostic | Cloud-agnostic | Cloud-agnostic |
| Policy (Kyverno) | Cloud-agnostic | Cloud-agnostic | Cloud-agnostic |

## Migration Considerations

When implementing workloads across multiple cloud providers, consider the following:

1. **Data Sovereignty**: Where data is stored and processed
2. **Service Compatibility**: Differences in service capabilities and limitations
3. **Cost Models**: Different pricing structures across cloud providers
4. **Identity Management**: Cross-cloud identity federation
5. **Monitoring and Operations**: Unified monitoring and management

## Next Steps

Continue to [Environment Management](05-environment-management.md) to understand how different environments are managed across cloud providers. 