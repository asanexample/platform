# Terragrunt Configuration Hierarchy

This document explains how the Terragrunt configuration system composes values
from multiple layers, how module sources are pinned, and how the cloud-aware
remote state routing works. It is intended for anyone who needs to add a new
environment, region, workload, or module to the infrastructure codebase.

---

## Table of Contents

1. [The 7-Layer Hierarchy](#the-7-layer-hierarchy)
2. [Layer-by-Layer Reference](#layer-by-layer-reference)
3. [How _base.hcl Composes Tags and Validates Safety](#how-_basehcl-composes-tags-and-validates-safety)
4. [How _versions.hcl Pins Module Sources](#how-_versionshcl-pins-module-sources)
5. [find_in_parent_folders Resolution Paths](#find_in_parent_folders-resolution-paths)
6. [Cloud-Aware Remote State Routing](#cloud-aware-remote-state-routing)
7. [Azure vs AWS: Parallel Structure Comparison](#azure-vs-aws-parallel-structure-comparison)
8. [GCP: Third Cloud Extension](#gcp-third-cloud-extension)
9. [Adding New Infrastructure](#adding-new-infrastructure)

---

## The 7-Layer Hierarchy

Every module-level `terragrunt.hcl` participates in a 7-layer configuration
hierarchy. Each layer can define variables that are consumed by layers above it
(narrower scope) or composed together by `_base.hcl`. Later (narrower) layers
override earlier (broader) layers when tags or inputs are merged.

```text
Layer 1 (broadest)    infra/root.hcl
    |                     Remote state, providers, global tags, cloud detection
    |
Layer 2               infra/live/{cloud}/common.hcl
    |                     Cloud-wide defaults: project tags, account/subscription maps
    |
Layer 3               infra/live/{cloud}/_versions.hcl
    |                     Module source paths, Helm chart version pins
    |
Layer 4               infra/live/{cloud}/{env}/common.hcl  (aliased as env.hcl)
    |                     Account/subscription ID, environment name, env-specific tags
    |
Layer 5               infra/live/{cloud}/{env}/{region}/region.hcl + network.hcl
    |                     Region name, abbreviation, features, CIDR blocks
    |
Layer 6               infra/live/{cloud}/{env}/{region}/{workload}/workload.hcl
    |                     Workload name, compliance tier, workload-specific tags
    |
Layer 7 (narrowest)   infra/live/{cloud}/{env}/{region}/{workload}/{module}/terragrunt.hcl
                          Final inputs, dependency declarations, module source
```

### Concrete Example: AWS Organizations Module

```text
infra/
  terragrunt.hcl                          <-- Layer 1: root
  live/
    aws/
      common.hcl                          <-- Layer 2: cloud-wide
      _versions.hcl                       <-- Layer 3: version pins
      _base.hcl                           <-- Composer (reads layers 2-6, exposes to layer 7)
      mgmt/
        common.hcl                        <-- Layer 4: environment (mgmt)
        global/
          region.hcl                      <-- Layer 5a: region (global/us-east-1)
          network.hcl                     <-- Layer 5b: network (empty for global)
          organizations/
            workload.hcl                  <-- Layer 6: workload (management)
            terragrunt.hcl               <-- Layer 7: module (organizations)
```

### Concrete Example: Azure AKS Core Module

```text
infra/
  terragrunt.hcl                          <-- Layer 1: root
  live/
    azure/
      common.hcl                          <-- Layer 2: cloud-wide
      _versions.hcl                       <-- Layer 3: version pins
      _base.hcl                           <-- Composer
      dev/
        common.hcl                        <-- Layer 4: environment (dev)
        eastus/
          region.hcl                      <-- Layer 5a: region (eastus)
          network.hcl                     <-- Layer 5b: network (CIDRs)
          platform/
            workload.hcl                  <-- Layer 6: workload (platform)
            aks_core/
              terragrunt.hcl             <-- Layer 7: module (aks_core)
```

---

## Layer-by-Layer Reference

### Layer 1: Root (`infra/root.hcl`)

The root configuration file applies to every module in every cloud. It provides:

- **OpenTofu binary selection.** All modules use `tofu` instead of `terraform`.
- **Cloud-aware remote state.** Detects whether the current module is under
  `live/aws/` or another cloud directory and configures the appropriate backend.
- **Provider generation.** Generates `provider_aws.tf`, `provider_azure.tf`, and
  `provider_gcp.tf` for all modules (unused providers are harmless).
- **Version constraints.** Generates `versions.tf` pinning provider versions
  (AWS 5.91.0, AzureRM 4.25.0, Google 6.26.0).
- **Global inputs.** Passes `common_tags` to all modules.
- **Cloud detection.** Parses the relative path to extract the cloud provider:

  ```hcl
  _path_parts_cloud = split("/", path_relative_to_include())
  _cloud            = try(local._path_parts_cloud[1], "azure")
  ```

  For a module at `live/aws/mgmt/global/organizations`, the split produces
  `["live", "aws", "mgmt", "global", "organizations"]`, so `_cloud = "aws"`.

### Layer 2: Cloud Common (`infra/live/{cloud}/common.hcl`)

Each cloud has its own `common.hcl` at the cloud root. This file defines:

- **Default workload name** (typically `"platform"`).
- **Base tags** shared across all environments in that cloud.
- **Account/subscription/project safety map.** A lookup table mapping environment
  names to expected account IDs (AWS), subscription IDs (Azure), or project IDs
  (GCP). Used by `_base.hcl` safety assertions to prevent cross-account deployment
  mistakes.

Example from AWS:

```hcl
environment_account_map = {
  "ops"  = "<PLATFORM_ACCOUNT_ID>"
  "mgmt" = "<MGMT_ACCOUNT_ID>"
}
```

Example from Azure:

```hcl
environment_subscription_map = {
  "dev" = "db4f1d99-0ec0-44eb-90de-41975f9bb68b"
  "ops" = "9dc5edc4-8c4e-41a1-a4f8-2183c4e91954"
}
```

### Layer 3: Version Pins (`infra/live/{cloud}/_versions.hcl`)

Centralizes all module source paths and Helm chart versions for a given cloud.
See the dedicated section below for details.

### Layer 4: Environment (`infra/live/{cloud}/{env}/common.hcl`)

Each environment directory contains a `common.hcl` (which also serves as `env.hcl`
for backward compatibility). This file defines:

- **Environment name** (`env` and `environment` for compatibility).
- **Account/subscription/project ID** for the target environment.
- **Environment-specific tags** (`env_tags`) including data classification,
  auto-shutdown policies, and account aliases.

Example values:

| Field               | AWS mgmt               | Azure dev                              |
|---------------------|-------------------------|----------------------------------------|
| environment         | `mgmt`                  | `dev`                                  |
| account/subscription| `<MGMT_ACCOUNT_ID>`          | `db4f1d99-0ec0-44eb-90de-41975f9bb68b` |
| DataClassification  | `Confidential`          | `Internal`                             |
| AutoShutdown        | (not set)               | `True`                                 |

### Layer 5: Region (`region.hcl` + `network.hcl`)

Each region directory contains two files:

- **`region.hcl`**: Region name, abbreviation (e.g., `eus` for `eastus`, `global`
  for `us-east-1` in the global context), region-specific feature flags, and region
  tags.
- **`network.hcl`**: Address space and subnet definitions. Empty for non-networked
  contexts (like the AWS global/organizations module).

### Layer 6: Workload (`workload.hcl`)

Each workload directory defines:

- **Workload name** (e.g., `platform`, `management`).
- **Compliance tier** (`standard`, `hipaa`, `pci`). This can drive conditional
  behavior in modules.
- **Workload tags** merged into the composed tag set.

### Layer 7: Module (`terragrunt.hcl`)

The leaf-level configuration. This is where:

- The `include` blocks pull in `_base.hcl` (for composed values) and the root
  `terragrunt.hcl` (for state/providers).
- `terraform.source` points to the module via `include.base.locals.module_source.<name>`.
- `inputs` provides module-specific values, referencing composed tags and other
  values from `include.base.locals`.

---

## How _base.hcl Composes Tags and Validates Safety

The `_base.hcl` file is the heart of the configuration system. It is not a
Terragrunt "root" config; it is included via `find_in_parent_folders()` by every
module-level `terragrunt.hcl` with `expose = true`, making its locals available
as `include.base.locals.*`.

### Tag Composition

Tags are merged in order of increasing specificity. Later layers overwrite
earlier layers for the same key:

```text
Step 1:  common_vars.locals.tags         (cloud-wide: ManagedBy, Project, CostCenter, Owner, DataClassification)
Step 2:  + env_vars.locals.env_tags      (environment: Environment, DataClassification override, AutoShutdown)
Step 3:  + region_vars.locals.region_tags (region: Region)
Step 4:  + workload_vars.locals.workload_tags (workload: Workload, ComplianceTier)
```

Result for the Azure dev/eastus/platform context:

```text
{
  ManagedBy          = "Terragrunt"        # from common (step 1)
  Project            = "Multi-Cloud Platform" # from common (step 1)
  CostCenter         = "Engineering"       # from common (step 1)
  Owner              = "Platform Team"     # from common (step 1)
  DataClassification = "Internal"          # from env (step 2, overwrites common)
  Environment        = "dev"               # from env (step 2)
  AutoShutdown       = "True"              # from env (step 2)
  SubscriptionName   = "platform-dev"      # from env (step 2)
  Region             = "eastus"            # from region (step 3)
  Workload           = "platform"          # from workload (step 4)
  ComplianceTier     = "standard"          # from workload (step 4)
}
```

### Safety Assertions

`_base.hcl` includes assertion locals that cause a plan-time failure if
configuration is inconsistent. These use the `tobool("error message")` trick:
when the condition is false, Terraform tries to convert the error string to a
boolean, which fails with a descriptive message.

#### Assertion 1: Environment Path Match

```hcl
_path_env = split("/", path_relative_to_include())[0]

_assert_env_path = (
  local._path_env == local.env
  ? true
  : tobool("SAFETY: directory '${local._path_env}' does not match env.hcl environment '${local.env}'")
)
```

This catches the scenario where someone copies a module from `dev/` into `prod/`
but forgets to update or create the correct `env.hcl`. The directory name must
match the `environment` value declared in `env.hcl`.

#### Assertion 2: Account/Subscription/Project ID Match

Each cloud variant checks the identity credential against the safety map:

| Cloud | Checks                                    | Map Source                          |
|-------|-------------------------------------------|-------------------------------------|
| AWS   | `account_id` vs `environment_account_map` | `aws/common.hcl`                   |
| Azure | `subscription_id` vs `environment_subscription_map` | `azure/common.hcl`        |
| GCP   | `project_id` vs `environment_project_map` | `gcp/common.hcl`                   |

If the map contains an entry for the current environment and the value does not
match what `env.hcl` declares, the plan fails. This prevents deploying dev
infrastructure into the production account.

#### Assertion 3: Workload Path Match (Azure only)

Azure's `_base.hcl` additionally checks that the workload directory name matches
`workload.hcl`:

```hcl
_path_workload = split("/", path_relative_to_include())[2]

_assert_workload_path = (
  local._path_workload == local.workload
  ? true
  : tobool("SAFETY: directory ... does not match workload.hcl workload ...")
)
```

### Flat Merge for Ad-Hoc Lookups

`_base.hcl` also provides `all_vars`, a flat merge of all config layers (excluding
version pins). This is useful when a module needs to look up a value from any layer
without knowing which layer defines it:

```hcl
all_vars = merge(
  common_vars.locals,
  env_vars.locals,
  region_vars.locals,
  network_vars.locals,
  workload_vars.locals,
)
```

---

## How _versions.hcl Pins Module Sources

Each cloud has a `_versions.hcl` file that centralizes module source paths and
Helm chart version pins. This is the single source of truth for "which code does
this module run?"

### Source Path Construction

All module sources are built relative to the repository root using `get_repo_root()`:

```hcl
source_base = "${get_repo_root()}/infra/modules"

module_source = {
  organizations   = "${local.source_base}/aws//organizations"
  networking      = "${local.source_base}/aws//networking"
  ...
}
```

The `//` in the path is Terraform's module subdirectory separator. It tells
Terraform to treat the right side as a subdirectory within the source, which
affects how relative paths within the module are resolved.

### Why get_repo_root()

Using `get_repo_root()` instead of relative paths provides two benefits:

1. **Stability.** The path resolves correctly regardless of which directory
   Terragrunt is invoked from.
2. **Migration readiness.** When the team is ready to move to a Terraform
   registry or Git tag-based versioning, only `_versions.hcl` needs to change.
   The comment block in the Azure version file documents this strategy:

   ```hcl
   # Monorepo (current): modules are sourced from get_repo_root() at HEAD.
   # Registry (future): change source_base to a registry URL and
   #   pin each module to a semver tag.
   ```

### Helm Chart Version Pins

Azure's `_versions.hcl` also pins Helm chart versions:

```hcl
helm_versions = {
  cilium           = "1.17.2"
  argocd           = "7.8.13"
  cert_manager     = "1.17.1"
  external_dns     = "1.16.1"
  external_secrets = "0.14.3"
  kyverno          = "3.3.7"
}
```

AWS's `_versions.hcl` currently has an empty `helm_versions` map, but the
structure is in place for future use.

### How Modules Consume the Source

In a module-level `terragrunt.hcl`:

```hcl
include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

terraform {
  source = include.base.locals.module_source.organizations
}
```

`_base.hcl` reads `_versions.hcl` and exposes `module_source` as a local.
The module `terragrunt.hcl` then references the specific key it needs.

---

## find_in_parent_folders Resolution Paths

Terragrunt's `find_in_parent_folders(filename)` walks up from the calling file's
directory until it finds a file matching the given name. Understanding the
resolution order is critical for debugging which config file a module actually
picks up.

### Resolution Diagram for an AWS Module

Starting from: `infra/live/aws/mgmt/global/organizations/terragrunt.hcl`

```text
find_in_parent_folders("aws/_base.hcl"):
  organizations/  --> global/  --> mgmt/  --> aws/
  Found: infra/live/aws/_base.hcl

find_in_parent_folders():   (no argument = root config (root.hcl))
  organizations/  --> global/  --> mgmt/  --> aws/  --> live/  --> infra/
  Found: infra/root.hcl

find_in_parent_folders("env.hcl"):     (called from within _base.hcl)
  _base.hcl is at infra/live/aws/, but path resolution is relative to
  the calling module (organizations/). Walks up:
  organizations/  --> global/  --> mgmt/
  Found: infra/live/aws/mgmt/common.hcl  (env.hcl symlink or direct match)

find_in_parent_folders("region.hcl"):
  organizations/  --> global/
  Found: infra/live/aws/mgmt/global/region.hcl

find_in_parent_folders("network.hcl"):
  organizations/  --> global/
  Found: infra/live/aws/mgmt/global/network.hcl

find_in_parent_folders("workload.hcl"):
  organizations/
  Found: infra/live/aws/mgmt/global/organizations/workload.hcl

find_in_parent_folders("common.hcl"):
  organizations/  --> global/  --> mgmt/
  Note: mgmt/common.hcl exists, but this is the env-level file.
  The cloud-level common.hcl is at aws/common.hcl.
  Actual resolution: first match wins = infra/live/aws/mgmt/common.hcl
```

### Resolution Diagram for an Azure Module

Starting from: `infra/live/azure/dev/eastus/platform/aks_core/terragrunt.hcl`

```text
find_in_parent_folders("azure/_base.hcl"):
  aks_core/  --> platform/  --> eastus/  --> dev/  --> azure/
  Found: infra/live/azure/_base.hcl

find_in_parent_folders():
  aks_core/  --> platform/  --> eastus/  --> dev/  --> azure/  --> live/  --> infra/
  Found: infra/root.hcl

find_in_parent_folders("env.hcl"):     (or "common.hcl" for env layer)
  aks_core/  --> platform/  --> eastus/  --> dev/
  Found: infra/live/azure/dev/common.hcl

find_in_parent_folders("region.hcl"):
  aks_core/  --> platform/  --> eastus/
  Found: infra/live/azure/dev/eastus/region.hcl

find_in_parent_folders("network.hcl"):
  aks_core/  --> platform/  --> eastus/
  Found: infra/live/azure/dev/eastus/network.hcl

find_in_parent_folders("workload.hcl"):
  aks_core/  --> platform/
  Found: infra/live/azure/dev/eastus/platform/workload.hcl

find_in_parent_folders("common.hcl"):
  aks_core/  --> platform/  --> eastus/  --> dev/
  Found: infra/live/azure/dev/common.hcl
```

### Important: common.hcl Shadowing

Both the cloud-level and environment-level directories contain a `common.hcl`.
The `find_in_parent_folders("common.hcl")` call from within `_base.hcl` resolves
relative to the calling module, so it finds the **environment-level** `common.hcl`
first (since it is closer in the directory tree).

To read the **cloud-level** `common.hcl`, `_base.hcl` uses a separate call
pattern. In practice, `_base.hcl` reads `common.hcl` (which resolves to the
environment level in some trees) and also directly reads the cloud-level common
via its known path. The `common_vars` local in `_base.hcl` reads
`find_in_parent_folders("common.hcl")`, which for the AWS organizations module
resolves to `mgmt/common.hcl`. However, the `environment_account_map` is defined
in `aws/common.hcl`, and this is the file that `common_vars` must resolve to for
the safety assertions to work. In practice, the environment-level `common.hcl`
files do not redefine the `tags` key expected by `_base.hcl`'s tag composition,
so the resolution works correctly as long as naming conventions are followed.

---

## Cloud-Aware Remote State Routing

The root `terragrunt.hcl` automatically routes state storage to the correct
backend based on the cloud provider directory.

### Detection Mechanism

```hcl
_path_parts_cloud = split("/", path_relative_to_include())
_cloud            = try(local._path_parts_cloud[1], "azure")
```

`path_relative_to_include()` returns the path from the root `terragrunt.hcl`
to the calling module. For `live/aws/mgmt/global/organizations`, the split
produces `["live", "aws", "mgmt", "global", "organizations"]`, and index `[1]`
is `"aws"`.

The fallback default is `"azure"` (via `try()`), which means any module not
under a recognized cloud directory defaults to Azure storage.

### Backend Configuration

| Cloud   | Backend    | Configuration                                                   |
|---------|------------|-----------------------------------------------------------------|
| AWS     | S3         | Bucket: `tfstate-mgmt-<MGMT_ACCOUNT_ID>`, Region: `us-east-1`, DynamoDB lock table: `terraform-locks`, Encryption: enabled |
| Default | Azure Blob | Subscription: `9dc5edc4-...`, Storage account: `tfstatemulticloud`, Container: `terraformstate`, Azure AD auth: enabled |

Both backends use `path_relative_to_include()` as the state key, which ensures
each module gets a unique state file path that mirrors the directory structure:

```text
State key for organizations module:
  live/aws/mgmt/global/organizations/terraform.tfstate

State key for Azure aks_core module:
  live/azure/dev/eastus/platform/aks_core/terraform.tfstate
```

---

## Azure vs AWS: Parallel Structure Comparison

The directory layout is intentionally parallel across clouds. This table shows
how the same architectural concepts map between AWS and Azure:

### Directory Structure

```text
infra/live/
  aws/                              azure/
    _base.hcl                         _base.hcl
    _versions.hcl                     _versions.hcl
    common.hcl                        common.hcl
    |                                 _envcommon/           <-- Azure has shared
    |                                   aks_core.hcl            module defaults
    |                                   networking.hcl
    |                                   ...
    mgmt/                             dev/
      common.hcl (env)                  common.hcl (env)
      global/                           eastus/
        region.hcl                        region.hcl
        network.hcl                       network.hcl
        organizations/                    platform/
          workload.hcl                      workload.hcl
          terragrunt.hcl                    aks_core/
                                              terragrunt.hcl
                                            networking/
                                              terragrunt.hcl
                                            ...
    ops/                              ops/
      common.hcl (env)                  common.hcl (env)
      us-east-1/                        westus/
        region.hcl                        region.hcl
        network.hcl                       network.hcl
                                          platform/
                                            workload.hcl
                                            aks_core/
                                              terragrunt.hcl
                                            ...
```

### Key Structural Differences

| Aspect              | AWS                                | Azure                              |
|---------------------|------------------------------------|------------------------------------|
| Environments        | `mgmt`, `ops`                      | `dev`, `ops`                       |
| Regions             | `global`, `us-east-1`              | `eastus`, `westus`                 |
| Workloads           | `management` (under mgmt/global)   | `platform` (under each region)     |
| _envcommon          | Not used (fewer modules)           | Used for shared module defaults    |
| Module count        | 2 (organizations, state-bootstrap) | 18+ per environment                |
| Safety assertions   | env path, account ID               | env path, workload path, subscription ID |
| Identity map        | `environment_account_map`          | `environment_subscription_map`     |

### _base.hcl Comparison

Both AWS and Azure `_base.hcl` files follow the same pattern:

1. Load all 6 config files via `read_terragrunt_config(find_in_parent_folders(...))`.
2. Create `all_vars` flat merge.
3. Extract commonly used scalars (`env`, `workload`, `compliance_tier`, `region`).
4. Expose `module_source` and `helm_versions` from `_versions.hcl`.
5. Compose tags via ordered `merge()`.
6. Run safety assertions using `tobool()` trick.

Azure adds one extra assertion (workload path match) and references
`subscription_id` instead of `account_id`. AWS references `account_id` and does
not assert workload path (since AWS currently has only one workload per region
directory).

### _versions.hcl Comparison

| Aspect          | AWS                    | Azure                                  |
|-----------------|------------------------|----------------------------------------|
| Module count    | 4 modules              | 27+ modules                            |
| Helm versions   | Empty map (future use) | 6 charts pinned                        |
| Source pattern   | `{repo_root}/infra/modules/aws//{name}` | `{repo_root}/infra/modules/azure//{name}` |
| Cloud-agnostic  | (none yet)             | cilium, argocd |

---

## GCP: Third Cloud Extension

GCP follows the identical pattern as AWS and Azure, with its own `_base.hcl`,
`common.hcl`, and directory structure under `infra/live/gcp/`.

### GCP-Specific Details

- **Safety map:** `environment_project_map` maps environment names to GCP project IDs.
- **Identity scalar:** `project_id` (instead of `account_id` or `subscription_id`).
- **Tags:** GCP uses "labels" but the same `tags` local is used for consistency.
- **Current state:** Only `ops/us-east1/` exists with `region.hcl` and `network.hcl`.
  No modules have been deployed yet.

The three-cloud pattern demonstrates the extensibility of the hierarchy: adding a
fourth cloud requires creating `infra/live/{cloud}/_base.hcl`, `_versions.hcl`,
and `common.hcl`, then populating environment directories following the same
7-layer convention.

---

## Adding New Infrastructure

### Adding a New Environment

1. Create the directory: `infra/live/{cloud}/{env}/`.
2. Create `common.hcl` (or `env.hcl`) with the environment name, account/subscription
   ID, and environment tags.
3. Add the environment to the safety map in `infra/live/{cloud}/common.hcl`
   (e.g., `environment_account_map["staging"] = "123456789012"`).
4. Create region subdirectories as needed.

### Adding a New Region

1. Create the directory: `infra/live/{cloud}/{env}/{region}/`.
2. Create `region.hcl` with the region name, abbreviation, and any feature flags.
3. Create `network.hcl` with address space and subnet definitions.

### Adding a New Workload

1. Create the directory: `infra/live/{cloud}/{env}/{region}/{workload}/`.
2. Create `workload.hcl` with the workload name, compliance tier, and tags.
3. Create module directories under the workload.

### Adding a New Module

1. Create the directory: `infra/live/{cloud}/{env}/{region}/{workload}/{module}/`.
2. Create `terragrunt.hcl` with the standard includes, source, and inputs:

   ```hcl
   include "base" {
     path   = find_in_parent_folders("{cloud}/_base.hcl")
     expose = true
   }

   include "root" {
     path = find_in_parent_folders()
   }

   terraform {
     source = include.base.locals.module_source.{module_key}
   }

   inputs = {
     tags = include.base.locals.tags
     # ... module-specific inputs
   }
   ```

3. Add the module source to `_versions.hcl` if it does not already exist.
