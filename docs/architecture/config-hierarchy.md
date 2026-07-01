# Terragrunt Configuration Hierarchy

This document explains how the Terragrunt configuration system composes values
from multiple layers, how module sources are pinned, and how remote state is
routed. It is intended for anyone who needs to add a new environment, region,
workload, or module to the infrastructure codebase.

The platform is **multi-cloud by design but AWS-first today** — only `infra/live/aws/`
exists. Azure and GCP are planned and the layout is deliberately cloud-parameterized
(`live/{cloud}/…`) so they can be added later without restructuring, but there are no
`live/azure/` or `live/gcp/` trees yet. This document describes the AWS reality and
notes where the pattern generalizes.

---

## Table of Contents

1. [The 6-Layer Hierarchy](#the-6-layer-hierarchy)
2. [Layer-by-Layer Reference](#layer-by-layer-reference)
3. [How _base.hcl Composes Tags and Validates Safety](#how-_basehcl-composes-tags-and-validates-safety)
4. [How _versions.hcl Pins Module Sources](#how-_versionshcl-pins-module-sources)
5. [find_in_parent_folders Resolution Paths](#find_in_parent_folders-resolution-paths)
6. [Remote State Routing](#remote-state-routing)
7. [Multi-Cloud Readiness](#multi-cloud-readiness)
8. [Adding New Infrastructure](#adding-new-infrastructure)

---

## The 6-Layer Hierarchy

Every unit-level `terragrunt.hcl` participates in a 6-layer configuration hierarchy.
Each layer can define values consumed by narrower layers or composed together by
`_base.hcl`. Narrower (later) layers override broader (earlier) layers when tags or
inputs are merged.

```text
Layer 1 (broadest)    infra/root.hcl
    |                     Remote state (S3 + DynamoDB), AWS provider, terraform_binary, cloud detection
    |
Layer 2               infra/live/aws/common.hcl
    |                     Cloud-wide defaults: base tags, loads secrets.enc.yaml, account-id safety map
    |
Layer 3               infra/live/aws/{env}/env.hcl
    |                     Account ID (from secrets), environment name, env-specific tags
    |
Layer 4               infra/live/aws/{env}/{region}/region.hcl + network.hcl
    |                     Region name, abbreviation, feature flags, CIDR blocks
    |
Layer 5               infra/live/aws/{env}/{region}/{workload}/workload.hcl
    |                     Workload name, compliance tier, workload-specific tags
    |
Layer 6 (narrowest)   infra/live/aws/{env}/{region}/{workload}/{unit}/terragrunt.hcl
                          Final inputs, dependency declarations, module source
```

Two **supporting files** sit alongside the hierarchy (they are loaded by `_base.hcl`
rather than being hierarchy layers themselves):

- `infra/live/aws/_versions.hcl` — module source paths and Helm chart version pins.
- `infra/live/aws/_base.hcl` — the composer that reads layers 2–5, exposes them to the
  unit via `include.base.locals.*`, composes tags, and runs safety assertions.

### Concrete Example: AWS Organizations Unit

```text
infra/
  root.hcl                                <-- Layer 1: root
  live/
    aws/
      common.hcl                          <-- Layer 2: cloud-wide
      _versions.hcl                       <-- supporting: version/source pins
      _base.hcl                           <-- supporting: composer (reads layers 2-5)
      secrets.enc.yaml                    <-- committed, SOPS-encrypted: account IDs, state bucket, emails
      mgmt/
        env.hcl                           <-- Layer 3: environment (mgmt)
        global/
          region.hcl                      <-- Layer 4a: region (global)
          network.hcl                     <-- Layer 4b: network (empty for global)
          organizations/
            workload.hcl                  <-- Layer 5: workload (management)
            terragrunt.hcl                <-- Layer 6: unit (organizations)
```

### Concrete Example: A Platform Cluster Unit

```text
infra/live/aws/
  platform/
    env.hcl                               <-- Layer 3: environment (platform)
    us-east-1/
      region.hcl                          <-- Layer 4a: region (us-east-1)
      network.hcl                         <-- Layer 4b: network (10.100.0.0/16)
      platform/
        workload.hcl                      <-- Layer 5: workload (platform)
        eks/
          terragrunt.hcl                  <-- Layer 6: unit (eks)
        networking/
          terragrunt.hcl                  <-- Layer 6: unit (networking)
        ...
```

---

## Layer-by-Layer Reference

### Layer 1: Root (`infra/root.hcl`)

The root configuration applies to every unit. It provides:

- **OpenTofu binary selection.** All units use `tofu` instead of `terraform`
  (`terraform_binary = "tofu"`).
- **Remote state.** An S3 backend with DynamoDB locking (see
  [Remote State Routing](#remote-state-routing)). The bucket, lock table, and access
  role come from the SOPS-encrypted `secrets.enc.yaml` (see
  [Config Secrets](#config-secrets-sops)).
- **Provider generation.** Generates `provider_aws.tf` (the only cloud provider
  generated today; Azure/GCP provider generation would be added when those clouds land).
- **Version constraints.** Generates a **fallback-only** `versions.tf` with AWS provider
  `~> 6.0` and `required_version >= 1.6.0` — emitted with `if_exists = "skip"`, so it applies only to a unit
  whose sourced module ships no `versions.tf`. Every shared module now declares its own `required_providers`
  (ADR-083), so in practice this block is skipped and the **module's** `versions.tf` is authoritative.
  (OpenTofu is pinned in `/.tool-versions`, currently 1.12.1.)
- **Cloud detection.** Parses the relative path to extract the cloud provider, defaulting
  to `aws`:

  ```hcl
  _path_parts_cloud = split("/", path_relative_to_include())
  _cloud            = try(local._path_parts_cloud[1], "aws")
  ```

  For a unit at `live/aws/mgmt/global/organizations`, the split produces
  `["live", "aws", "mgmt", "global", "organizations"]`, so `_cloud = "aws"`. The
  detection seam is kept for future multi-cloud; today every path resolves to `aws`.

### Layer 2: Cloud Common (`infra/live/aws/common.hcl`)

The cloud-root `common.hcl` defines:

- **Default workload name** (`platform`) and **org/resource name prefix** (`org_name`,
  currently `asanexample`, used for globally-unique names like environment S3 buckets).
- **Base tags** shared across all environments.
- **Secrets load + account-id safety map.** It loads config secrets (account IDs, emails,
  SSO config) and exposes `environment_account_map = local._secrets.account_ids` — a lookup
  from environment name to expected AWS account ID, used by `_base.hcl` safety assertions to
  prevent cross-account deployment mistakes. (Secrets handling is detailed under
  [Remote State Routing → Config Secrets](#config-secrets-sops) — they are SOPS-encrypted and
  committed, not gitignored plaintext.)

### Layer 3: Environment (`infra/live/aws/{env}/env.hcl`)

Each environment directory contains an `env.hcl` defining:

- **Environment name** (`env` / `environment`). The deployed environments are
  `mgmt`, `platform`, `preprod`, `prod`, and `test`.
- **Account ID** for the target environment (sourced from `secrets.enc.yaml`).
- **Environment-specific tags** (`env_tags`) including data classification.

### Layer 4: Region (`region.hcl` + `network.hcl`)

Each region directory contains two files:

- **`region.hcl`**: region name, abbreviation (e.g., `use1` for `us-east-1`, `global`
  for non-regional units), region feature flags, and region tags.
- **`network.hcl`**: VPC address space and the `subnet_tiers` map (CIDR allocation, the
  authoritative source per ADR-015). Empty for non-networked contexts like
  `mgmt/global`.

### Layer 5: Workload (`workload.hcl`)

Each workload directory defines:

- **Workload name** (e.g., `platform`, `management`).
- **Compliance tier** (`standard`, `hipaa`, `pci` — ADR-013). Drives conditional
  behavior in modules (e.g., regulated tiers require `runAsNonRoot`).
- **Workload tags** merged into the composed tag set.

### Layer 6: Unit (`terragrunt.hcl`)

The leaf-level configuration. This is where:

- The `include` blocks pull in `_base.hcl` (for composed values, `expose = true`) and
  the root config (for state/providers).
- `terraform.source` points to the module via
  `include.base.locals.module_source.<name>`.
- `inputs` provides unit-specific values, referencing composed tags and other values
  from `include.base.locals`, plus `dependency` blocks (with `mock_outputs`) for
  cross-unit wiring.

---

## How _base.hcl Composes Tags and Validates Safety

`_base.hcl` is the heart of the configuration system. It is **not** a Terragrunt "root"
config; it is included via `find_in_parent_folders("aws/_base.hcl")` by every unit-level
`terragrunt.hcl` with `expose = true`, making its locals available as
`include.base.locals.*`. It reads six configs: `env.hcl`, `region.hcl`, `network.hcl`,
`workload.hcl`, `common.hcl`, and `aws/_versions.hcl`.

### Tag Composition

Tags are merged in order of increasing specificity. Later layers overwrite earlier
layers for the same key:

```text
Step 1:  common_vars.locals.tags          (cloud-wide: ManagedBy, Project, Owner, ...)
Step 2:  + env_vars.locals.env_tags        (environment: Environment, DataClassification)
Step 3:  + region_vars.locals.region_tags  (region: Region)
Step 4:  + workload_vars.locals.workload_tags (workload: Workload, ComplianceTier)
```

Result for the `platform/us-east-1/platform` context (illustrative):

```text
{
  ManagedBy          = "Terragrunt"
  Project            = "Reference Platform"
  Owner              = "Platform Team"
  Environment        = "platform"
  Region             = "us-east-1"
  Workload           = "platform"
  ComplianceTier     = "standard"
}
```

### Safety Assertions

`_base.hcl` includes assertion locals that cause a plan-time failure if configuration is
inconsistent. These use the `tobool("error message")` trick: when the condition is
false, OpenTofu tries to convert the error string to a boolean, which fails with a
descriptive message. There are **two** assertions:

#### Assertion 1: Environment Path Match

```hcl
_path_env = split("/", path_relative_to_include())[0]

_assert_env_path = (
  local._path_env == local.env
  ? true
  : tobool("SAFETY: directory '${local._path_env}' does not match env.hcl environment '${local.env}'")
)
```

This catches the scenario where someone copies a unit from `preprod/` into `prod/` but
forgets to update the `env.hcl`. The directory name must match the `environment` value
declared in `env.hcl`.

#### Assertion 2: Account ID Match

```hcl
_assert_account = (
  local._expected_account == null ||
  local._expected_account == local.env_vars.locals.account_id
  ? true
  : tobool("SAFETY: env '${local.env}' expects account '${local._expected_account}' but env.hcl has '${local.env_vars.locals.account_id}'")
)
```

`_expected_account` is looked up from `environment_account_map` (from the config secrets),
defaulting to `null` when the map has no entry for the current environment. The `== null ||`
guard makes the assertion a no-op for environments not in the map; when the map *does* have
an entry and it does not match what `env.hcl` declares, the plan fails — preventing, e.g.,
deploying preprod infrastructure into the prod account.

### Flat Merge for Ad-Hoc Lookups

`_base.hcl` also provides `all_vars`, a flat merge of all config layers (excluding
version pins), useful when a unit needs a value from any layer without knowing which
layer defines it:

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

`infra/live/aws/_versions.hcl` centralizes module source paths and Helm chart version
pins — the single source of truth for "which code does this unit run, at which chart
version?"

### Source Path Construction

All module sources are built relative to the repository root using `get_repo_root()`:

```hcl
source_base = "${get_repo_root()}/infra/modules"

module_source = {
  organizations = "${local.source_base}/aws//organizations"
  networking    = "${local.source_base}/aws//networking"
  eks           = "${local.source_base}/aws//eks"
  # ... ~66 modules total (shared modules + aws/ modules)
}
```

The `//` is OpenTofu's module-subdirectory separator. There are roughly **61** module
sources registered (the shared cloud-agnostic modules plus the `aws/` modules).

### Why get_repo_root()

Using `get_repo_root()` instead of relative paths provides:

1. **Stability.** The path resolves correctly regardless of which directory Terragrunt
   is invoked from.
2. **Migration readiness.** When the team is ready to move to Git-tag or registry-based
   versioning, only `_versions.hcl` changes — every unit references modules indirectly
   through `module_source`.

### Helm Chart Version Pins

`_versions.hcl` also pins Helm chart versions in a `helm_versions` map (~28 charts),
so chart upgrades are a one-line change reviewed in one place. Current pins include:

```hcl
helm_versions = {
  cilium                = "1.19.4"
  argocd                = "9.5.14"
  external_secrets      = "0.14.3"
  kyverno               = "3.8.1"
  kube_prometheus_stack = "87.5.0"
  mimir                 = "6.0.6"
  # ... etc.
}
```

### How Units Consume the Source

```hcl
include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

terraform {
  source = include.base.locals.module_source.eks
}
```

`_base.hcl` reads `_versions.hcl` and exposes `module_source` and `helm_versions` as
locals; the unit references the specific key it needs.

---

## find_in_parent_folders Resolution Paths

Terragrunt's `find_in_parent_folders(filename)` walks up from the calling file's
directory until it finds a matching file. Understanding the resolution order is critical
for debugging which config file a unit actually picks up.

### Resolution Diagram

Starting from: `infra/live/aws/mgmt/global/organizations/terragrunt.hcl`

```text
find_in_parent_folders("aws/_base.hcl"):
  organizations/ --> global/ --> mgmt/ --> aws/
  Found: infra/live/aws/_base.hcl

find_in_parent_folders():   (no argument = the root config, root.hcl)
  organizations/ --> ... --> aws/ --> live/ --> infra/
  Found: infra/root.hcl

find_in_parent_folders("env.hcl"):     (called from within _base.hcl)
  organizations/ --> global/ --> mgmt/
  Found: infra/live/aws/mgmt/env.hcl

find_in_parent_folders("region.hcl"):
  organizations/ --> global/
  Found: infra/live/aws/mgmt/global/region.hcl

find_in_parent_folders("network.hcl"):
  organizations/ --> global/
  Found: infra/live/aws/mgmt/global/network.hcl

find_in_parent_folders("workload.hcl"):
  organizations/
  Found: infra/live/aws/mgmt/global/organizations/workload.hcl

find_in_parent_folders("common.hcl"):
  organizations/ --> global/ --> mgmt/ --> aws/
  Found: infra/live/aws/common.hcl   (the single cloud-level common.hcl)
```

There is one `common.hcl` (cloud level) and one `env.hcl` per environment, so there is
no shadowing ambiguity — `common.hcl` always resolves to the cloud-level file and
`env.hcl` to the environment-level file.

---

## Remote State Routing

The root config configures the S3 backend. State is keyed by directory path so each unit
gets a unique state file mirroring the tree.

### Backend Configuration

```hcl
remote_state {
  backend = "s3"
  config = {
    bucket         = local._secrets.state_bucket               # from secrets.enc.yaml
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
    role_arn       = local._secrets.state_role_arn             # TerraformStateAccess
  }
}
```

The secrets decode to a **flat** map, so the accessors are `local._secrets.<key>` (e.g.
`local._secrets.state_bucket`, `local._secrets.state_role_arn`) — not a nested
`.locals.*`. The bucket and the state-access role ARN come from the config secrets (the
bucket is created once by the `state_bootstrap` module — ADR-006). The `_cloud` detection
seam exists for future multi-cloud backend routing, but today the backend is
unconditionally S3.

### Config Secrets (SOPS) {#config-secrets-sops}

Sensitive values (account IDs, emails, SSO URLs, the state bucket + state-access role ARN)
live in `infra/live/aws/secrets.enc.yaml` — **committed to the repo but SOPS-encrypted**
(ADR-066). Both `root.hcl` and `common.hcl` decrypt it inline at config-load time:

```hcl
_secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1"
  ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals
  : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))
```

The normal path decrypts `secrets.enc.yaml` via the management `platform-sops` KMS key.
Plaintext `secrets.hcl` is **only** a greenfield bootstrap fallback, gated behind
`TG_SOPS_BOOTSTRAP=1` — needed solely on a true from-zero bootstrap before the
`platform-sops` key exists (the `state-bootstrap` and KMS-key units include `root.hcl`, so
they cannot decrypt what has not been created yet). Both branches yield the same flat map,
so `local._secrets.<key>` accessors are identical regardless of which path is taken.

State key example:

```text
live/aws/mgmt/global/organizations/terraform.tfstate
live/aws/platform/us-east-1/platform/eks/terraform.tfstate
```

---

## Multi-Cloud Readiness

The hierarchy is cloud-parameterized (`live/{cloud}/…`, `_cloud` detection, per-cloud
`common.hcl`/`_versions.hcl`/`_base.hcl`) so Azure and GCP can be added later without
restructuring — this is the same "multi-cloud-by-design, AWS-first" posture as the
shared modules (ADR-001, ADR-008). **No `live/azure/` or `live/gcp/` tree exists today.**

When a second cloud is added, it would follow the identical convention:

- `infra/live/{cloud}/_base.hcl`, `_versions.hcl`, `common.hcl`.
- An environment → identity safety map (`environment_subscription_map` for Azure,
  `environment_project_map` for GCP) mirroring `environment_account_map`.
- The cloud-specific identity scalar (`subscription_id` / `project_id`) in the account
  assertion, and provider generation for that cloud in `root.hcl`.
- Cloud-agnostic shared modules (Cilium, ArgoCD, External Secrets, etc.) reused with a
  cloud-specific backend/identity; cloud-specific modules under `infra/modules/{cloud}/`.

Until then, treat the structure as AWS-only.

---

## Adding New Infrastructure

### Adding a New Environment

1. Create `infra/live/aws/{env}/`.
2. Create `env.hcl` with the environment name, account ID, and environment tags.
3. Add the environment → account-ID entry to `account_ids` in `secrets.enc.yaml` (edit via
   `sops`; surfaced as `environment_account_map`), so the account safety assertion can
   validate it.
4. Create region subdirectories as needed.

### Adding a New Region

1. Create `infra/live/aws/{env}/{region}/`.
2. Create `region.hcl` with the region name, abbreviation, and feature flags.
3. Create `network.hcl` with the VPC address space and `subnet_tiers` (ADR-015).

### Adding a New Workload

1. Create `infra/live/aws/{env}/{region}/{workload}/`.
2. Create `workload.hcl` with the workload name, compliance tier, and tags.

### Adding a New Unit

1. Create `infra/live/aws/{env}/{region}/{workload}/{unit}/`.
2. Create `terragrunt.hcl` with the standard includes, source, and inputs:

   ```hcl
   include "base" {
     path   = find_in_parent_folders("aws/_base.hcl")
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
     # ... unit-specific inputs and dependency blocks
   }
   ```

3. Add the module source to `_versions.hcl` if it does not already exist.
