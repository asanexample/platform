# Tagging Strategy

## Overview

The platform uses a hierarchical tagging system that composes tags from
four layers: cloud-level defaults, environment overrides, region metadata,
and optional workload tags. Tags are merged in `_base.hcl` and passed
explicitly to every module via the `tags` input variable.

## Tagging Principles

1. **Hierarchical composition** -- tags are defined at the layer where they
   are known and merged at apply time, so environment-specific values
   override cloud-level defaults without duplication.
2. **Explicit over implicit** -- tags flow through Terragrunt `inputs`, not
   provider-level `default_tags`. Every module receives and applies tags
   explicitly, keeping modules cloud-agnostic and portable.
3. **Consistency** -- the same tag keys are used across AWS, Azure, and GCP.
4. **Enforcement** -- required tags are enforced by SCPs on AWS. Azure and
   GCP enforcement is not yet implemented.

## Standard Tags

Every resource receives these tags via the merge chain:

| Tag Key | Source Layer | Description | Example |
|---------|-------------|-------------|---------|
| `ManagedBy` | common.hcl | Tool managing the resource | `Terragrunt` |
| `Project` | common.hcl | Project name | `Multi-Cloud Platform` |
| `DataClassification` | common.hcl / env.hcl | Data sensitivity | `Internal`, `Confidential` |
| `CostCenter` | common.hcl | Cost allocation group | `Engineering` |
| `Owner` | common.hcl | Responsible team | `Platform Team` |
| `Environment` | env.hcl | Deployment environment | `platform`, `prod`, `dev` |
| `AutoShutdown` | env.hcl | Non-prod shutdown automation | `True`, `False` |
| `AccountAlias` | env.hcl (AWS) | AWS account alias | `platform-use1` |
| `SubscriptionName` | env.hcl (Azure) | Azure subscription name | `vip-ops` |
| `Region` | region.hcl | Deployment region | `us-east-1`, `westus` |
| `Name` | resource-level | Resource identifier | `platform-use1-vpc` |

### Optional Tags

These appear only when the workload layer defines them:

| Tag Key | Source Layer | Description | Example |
|---------|-------------|-------------|---------|
| `Workload` | workload.hcl | Workload name | `management` |
| `ComplianceTier` | workload.hcl | Compliance level | `standard`, `hipaa`, `pci` |

## Tag Composition

Tags are merged in `_base.hcl` using Terraform's `merge()` function. Later
layers override earlier ones:

```text
common.hcl         (cloud-level defaults)
  ↓ merge
env.hcl            (environment overrides)
  ↓ merge
region.hcl         (region metadata)
  ↓ merge
workload.hcl       (workload-specific tags)
  ↓
_base.hcl          tags = merge(common, env, region, workload)
  ↓
terragrunt.hcl     inputs = { tags = include.base.locals.tags }
  ↓
module             variable "tags" { type = map(string) }
  ↓
resource           tags = merge(var.tags, { Name = "..." })
```

AWS and Azure both use this four-layer merge. GCP currently uses three
layers (no workload tags).

### Source Files

| Cloud | Layer | File |
|-------|-------|------|
| AWS | Common | `infra/live/aws/common.hcl` |
| AWS | Environment | `infra/live/aws/{env}/env.hcl` |
| AWS | Region | `infra/live/aws/{env}/{region}/region.hcl` |
| AWS | Workload | `infra/live/aws/{env}/{region}/{workload}/workload.hcl` |
| AWS | Merge | `infra/live/aws/_base.hcl` |
| Azure | Common | `infra/live/azure/common.hcl` |
| Azure | Environment | `infra/live/azure/{env}/common.hcl` |
| Azure | Region | `infra/live/azure/{env}/{region}/region.hcl` |
| Azure | Workload | `infra/live/azure/{env}/{region}/{workload}/workload.hcl` |
| Azure | Merge | `infra/live/azure/_base.hcl` |

## Module Implementation

All modules define a standard `tags` variable:

```hcl
variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
```

Resources merge `var.tags` with a resource-specific `Name` tag:

```hcl
resource "aws_vpc" "this" {
  cidr_block = var.vpc_cidr
  tags       = merge(var.tags, { Name = var.vpc_name })
}
```

This pattern ensures every resource inherits the full tag set while adding
its own identifier.

## Tag Enforcement

### AWS: Service Control Policies

The `require-tagging` SCP denies creation of EC2 instances, S3 buckets, and
RDS databases that are missing required tags. The required tags default to:

- `Environment`
- `ManagedBy`
- `Owner`

The SCP is defined in `infra/modules/aws/organizations/scps.tf` and
attached to the Workloads organizational unit. It uses `aws:RequestTag`
conditions to enforce tag presence at creation time.

### Azure

No centralized tag enforcement is implemented yet. Azure modules define
`default_tags` locally as a fallback, but there is no Azure Policy
assignment requiring tags.

### GCP

No tag enforcement is implemented yet.

## Next Steps

Continue to [Module Design Principles](13-module-design.md) to understand
how the VIP Platform modules are designed and implemented.
