# Environment Management

## Overview

The VIP Platform supports multiple environments (development, testing, production) across cloud providers and regions. This document outlines the environment management strategy, including environment isolation, configuration patterns, and promotion workflows.

## Environment Types

The platform supports the following environment types:

1. **ops**: Shared operational infrastructure (CI/CD, ArgoCD, observability tooling)
2. **dev**: Active development and early testing
3. **test/qa**: Pre-production validation and quality assurance
4. **prod**: Live workloads requiring maximum reliability

Each environment maps to exactly one cloud subscription or account, enforced by safety validations in `_base.hcl` (see below).

## Environment Isolation

Environments are isolated at multiple layers: subscription/account boundaries, network address space, identity, and Terragrunt configuration hierarchy.

### Subscription / Account Isolation

Every environment is bound to a dedicated cloud subscription (Azure) or account (AWS/GCP). The mapping is declared once in the cloud-level `common.hcl`:

```hcl
# infra/live/azure/common.hcl
environment_subscription_map = {
  "dev" = "db4f1d99-..."
  "ops" = "9dc5edc4-..."
}
```

`_base.hcl` validates at Terragrunt parse time that the `subscription_id` declared in `env.hcl` matches the expected value from this map. If someone copies an `env.hcl` into the wrong directory or edits the subscription ID, Terragrunt refuses to plan or apply. See **Safety Validations** below for the exact mechanism.

### Network Isolation

Each environment has its own dedicated network resources:

- Separate VNets/VPCs per environment and region
- Non-overlapping CIDR ranges allocated via `network.hcl`
- Controlled cross-environment access (default deny)

### Identity Isolation

Each environment uses its own Azure subscription (or AWS account / GCP project), so managed identities, service principals, and IAM roles are scoped to a single environment by default. Workload identity federation binds Kubernetes service accounts to cloud identities within the same subscription boundary, preventing cross-environment privilege escalation.

## Configuration Management

The platform uses Terragrunt's configuration hierarchy to manage environment-specific settings. The config files are loaded broadest-to-narrowest, with later layers overriding earlier ones:

| Layer | File(s) | Scope |
|-------|---------|-------|
| Root | `infra/terragrunt.hcl` | Remote state, providers, global tags |
| Cloud | `infra/live/azure/common.hcl` | Cloud-wide defaults (prefix, project tags, subscription map) |
| Versions | `infra/live/azure/_versions.hcl` | Module source paths and Helm chart version pins |
| Environment | `infra/live/azure/{env}/env.hcl` | Subscription, env tags, shutdown policies |
| Region | `infra/live/azure/{env}/{region}/region.hcl`, `network.hcl` | Region name, CIDR blocks |
| Defaults | `infra/live/azure/_envcommon/*.hcl` | Module defaults shared across environments |
| Module | `infra/live/azure/{env}/{region}/{module}/terragrunt.hcl` | Final overrides |

### The `env.hcl` Symlink Pattern

Within each environment directory (e.g., `infra/live/azure/dev/`), the canonical configuration lives in `common.hcl`. A symlink `env.hcl -> common.hcl` exists so that `_base.hcl` can locate it with `find_in_parent_folders("env.hcl")`. This avoids name collisions with the cloud-level `common.hcl` while keeping a single source of truth per environment.

```
infra/live/azure/dev/
  common.hcl          # canonical environment config (subscription_id, env tags, etc.)
  env.hcl -> common.hcl   # symlink for _base.hcl discovery
```

### The `_base.hcl` Include Pattern

Every module-level `terragrunt.hcl` includes `_base.hcl` to load the full config hierarchy automatically:

```hcl
include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}
```

Module configs then reference values as `include.base.locals.<name>` (e.g., `include.base.locals.env`, `include.base.locals.module_source.networking`).

## Safety Validations

`_base.hcl` contains two assertions that fire at Terragrunt parse time, before any Terraform plan or apply runs. Both use the `tobool("error message")` pattern to produce an immediate, readable failure.

### 1. Path-Environment Consistency

The directory path is split to extract the environment segment (e.g., `dev/eastus/networking` yields `dev`). If this does not match the `environment` value in `env.hcl`, Terragrunt halts:

```
SAFETY: directory 'dev' does not match env.hcl environment 'ops'
```

This prevents a misconfigured or misplaced `env.hcl` from deploying resources under the wrong environment identity.

### 2. Subscription Mapping

The `subscription_id` declared in `env.hcl` is compared against the expected value in `common.hcl`'s `environment_subscription_map`. A mismatch produces:

```
SAFETY: env 'dev' expects subscription 'db4f1d99-...' but env.hcl has '9dc5edc4-...'
```

Together these validations guarantee that every module deploys into the correct environment and subscription, even if configuration files are copy-pasted between directories.

## Workload Isolation

Within each environment and region, resources are further isolated by **workload**. Each workload directory contains a `workload.hcl` that declares the workload name, compliance tier, and workload-specific tags. The full directory path becomes:

```
infra/live/{cloud}/{env}/{region}/{workload}/{module}/terragrunt.hcl
```

### Subscription Topology

Subscriptions are organized by workload purpose, not by team:

| Management Group | Subscription | Purpose |
|------------------|-------------|---------|
| platform | platform-connectivity-{prod,nonprod} | Hub networking, DNS, firewall |
| platform | platform-shared-{prod,nonprod} | Shared clusters, observability, ACR |
| platform | platform-data-{prod,nonprod} | Shared data services |
| regulated | regulated-hipaa-prod | HIPAA-isolated compute and data |
| regulated | regulated-pci-prod | PCI CDE isolated compute and data |

Standard-tier workloads (platform, connectivity, data) share clusters via vCluster. HIPAA and PCI workloads get dedicated clusters and isolated VNets within their own subscriptions.

### State Management per Workload

Terraform state is isolated per workload and environment using path-based keys:

```
{cloud}/{env}/{region}/{workload}/{module}/terraform.tfstate
```

Each workload gets its own state namespace, preventing cross-workload state collisions and limiting the blast radius of any state corruption. The root `terragrunt.hcl` generates this key automatically from the directory path.

## Promotion Workflow

Infrastructure changes flow through environments in order: **dev** (or **ops** for shared tooling) then **test/qa** then **prod**. Each promotion is a separate Terragrunt apply against the target environment's directory tree. Because module sources are currently pinned to the monorepo HEAD (see `_versions.hcl`), all environments share the same module code. When the platform moves to registry-based modules, version pins in `_versions.hcl` will allow independent promotion per environment.

## Next Steps

Continue to [CIDR Allocation Strategy](06-cidr-allocation.md) to understand how IP address spaces are managed across environments. 