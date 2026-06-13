# Environment Management

## Overview

Each environment maps to a dedicated AWS account. Isolation is enforced at account
boundaries, network address space, and identity scope. Terragrunt safety validations
prevent cross-environment deployment mistakes at parse time. (Azure subscriptions / GCP
projects would map the same way when those clouds land — they are not deployed today.)

## Current Environments

Only **AWS** is deployed (5 accounts). Azure/GCP are planned (no `live/azure`, `live/gcp`).

| Environment | Account ID | Purpose | Deployed |
|-------------|-----------|---------|----------|
| mgmt | <MGMT_ACCOUNT_ID> | Organizations, Identity Center, Terraform state, GitHub OIDC | Yes |
| platform | <PLATFORM_ACCOUNT_ID> | EKS hub cluster + platform services + observability + IAM roles | Yes (full stack) |
| test | <TEST_ACCOUNT_ID> | Terratest CI sandbox | Yes (GitHub OIDC + PlatformDeployer) |
| preprod | <PREPROD_ACCOUNT_ID> | Pre-production environment workloads | **Yes (full environment cluster: EKS, Crossplane-Composition environments, Kyverno Enforce, Falco, Pod Identity)** |
| prod | <PROD_ACCOUNT_ID> | Production workloads | Networking + org scaffolding (no cluster yet) |

## Isolation Boundaries

### Account / Subscription Isolation

Every environment is bound to a single cloud account or subscription.
The mapping is declared in `common.hcl` at the cloud level:

```hcl
# AWS
environment_account_map = {
  "platform" = "<PLATFORM_ACCOUNT_ID>"
  "mgmt"     = "<MGMT_ACCOUNT_ID>"
  "preprod"  = "<PREPROD_ACCOUNT_ID>"
  "prod"     = "<PROD_ACCOUNT_ID>"
}
```

`_base.hcl` validates that the account/subscription ID in `env.hcl`
matches this map. If someone copies an env.hcl into the wrong directory,
Terragrunt refuses to plan. See
[Configuration Hierarchy: Safety Assertions](../../docs/architecture/config-hierarchy.md#how-_basehcl-composes-tags-and-validates-safety)
for the exact mechanism.

### Network Isolation

Each environment gets its own VPC or VNet with a dedicated CIDR block.
Address spaces do not overlap across environments:

| Cloud | Environment | CIDR |
|-------|-------------|------|
| AWS | platform | `10.100.0.0/16` |
| AWS | preprod | `10.101.0.0/16` |
| AWS | prod | `10.102.0.0/16` |

Cross-environment connectivity is not enabled by default. VPC peering or
transit gateway would be added explicitly if needed.

See [CIDR Allocation Strategy](06-cidr-allocation.md) for the full
allocation scheme.

### Identity Isolation

Cloud identities are scoped to a single account or subscription:

- **AWS**: IAM roles are account-scoped. Cross-account access uses
  explicit trust policies (e.g., PlatformDeployer trusts the management
  account). IRSA binds Kubernetes service accounts to IAM roles within
  the same account.
- **Azure**: Managed identities and federated credentials are
  subscription-scoped. Workload identity federation binds Kubernetes
  service accounts to managed identities within the same subscription.

### SCP / Policy Guardrails

On AWS, Service Control Policies enforce guardrails at the organization
level:

| OU | SCPs |
|----|------|
| Root | baseline-guardrails, protect-security-services, enforce-encryption, deny-regions |
| Platform | protect-data-and-network |
| Workloads | protect-data-and-network, require-tagging, restrict-iam-users |

The `require-tagging` SCP denies creation of EC2, S3, and RDS resources
without `Environment`, `ManagedBy`, and `Owner` tags.

## Workloads

Within each environment and region, infrastructure is grouped by
**workload** -- a logical boundary that determines compliance tier,
cluster topology, and resource tags.

```text
infra/live/{cloud}/{env}/{region}/{workload}/{module}/terragrunt.hcl
```

Each workload directory has a `workload.hcl` declaring its identity:

```hcl
locals {
  workload        = "platform"
  compliance_tier = "standard"
  workload_tags   = {
    Workload       = "platform"
    ComplianceTier = "standard"
  }
}
```

### Compliance Tiers

The `compliance_tier` value drives cluster topology and security
controls:

| Tier | Cluster Model | Network | Extra Controls |
|------|--------------|---------|----------------|
| standard (SOC2) | Shared cluster, **namespace isolation** (vCluster deferred, ADR-033) | Spoke VPC | RBAC, NetworkPolicies, private endpoints, audit logging |
| hipaa | Dedicated cluster | Isolated network | CMK encryption, 365-day logs, host encryption, restricted PSS + read-only rootfs |
| pci | Dedicated cluster | CDE-segmented network | All HIPAA controls + WAF, IDS, deny-all network policy |

Currently all deployed workloads use the `standard` tier. HIPAA and PCI
tiers are designed but not yet deployed.

## Environment-Specific Configuration

Each environment defines its settings in `env.hcl` (or `common.hcl` at
the environment level):

| Setting | Purpose | Example |
|---------|---------|---------|
| `environment` | Environment name | `platform`, `dev`, `prod` |
| `account_id` / `subscription_id` | Cloud identity | `<PLATFORM_ACCOUNT_ID>` |
| `DataClassification` | Data sensitivity tag | `Internal`, `Confidential` |
| `AutoShutdown` | Non-prod cost optimization | `True`, `False` |

These values merge into the tag hierarchy via `_base.hcl`. For the full
configuration mechanics, see
[Terragrunt Configuration Hierarchy](../../docs/architecture/config-hierarchy.md).

## State Isolation

Terraform state is isolated per environment, region, workload, and
module. The state key mirrors the directory path:

```text
live/aws/platform/us-east-1/platform/eks/terraform.tfstate
live/aws/preprod/us-east-1/platform/tenant-claims/terraform.tfstate
```

This prevents cross-environment state collisions and limits the blast
radius of state corruption to a single module.

## Promotion Workflow

Infrastructure changes flow through environments in order. Because
module sources are pinned to the monorepo HEAD (via `_versions.hcl`),
all environments share the same module code. Each promotion is a
separate Terragrunt apply against the target environment directory.

When the platform migrates to registry-based modules, `_versions.hcl`
version pins will allow independent promotion per environment.

## Next Steps

Continue to [CIDR Allocation Strategy](06-cidr-allocation.md) to
understand how IP address spaces are managed across environments and
clouds.
