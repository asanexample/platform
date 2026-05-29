# ADR-001: Multi-Cloud Terragrunt Monorepo Structure

**Date:** 2025-05-15

**Status:** Accepted

## Context

The organization operates infrastructure across three cloud providers: Azure (mature, production
workloads), AWS (actively being built out with Organizations and account vending), and GCP
(operational). Managing infrastructure-as-code across multiple clouds presents several fundamental
challenges:

1. **Configuration consistency.** Each cloud has its own provider semantics, authentication model,
   state backend, and resource naming conventions. Without a unifying structure, teams duplicate
   boilerplate, drift on conventions, and lose the ability to reason about the estate as a whole.

2. **Module sourcing strategy.** The Terraform ecosystem offers public registries, Git-based
   sourcing, and local monorepo sourcing. Each carries trade-offs in version control, review
   velocity, and dependency management.

3. **Configuration layering.** Real-world infrastructure has hierarchical configuration: some values
   are global (tool versions, tagging standards), some are cloud-specific (provider version pins),
   some are environment-specific (account IDs, compliance tiers), and some are workload-specific
   (network CIDRs, feature flags). Flat configuration files become unmaintainable as the matrix of
   clouds x environments x regions x workloads grows.

4. **Team scaling.** Multiple engineers need to work on different clouds and environments
   simultaneously without merge conflicts or configuration interference.

5. **Audit and compliance.** Regulated workloads require clear traceability from a deployed resource
   back to the code and configuration that produced it. Scattered repositories make this difficult.

### Constraints

- OpenTofu is the execution engine (not HashiCorp Terraform), set via `terraform_binary = "tofu"`.
- Azure is the most mature cloud; any structural decision must not disrupt existing Azure workflows.
- The team is small enough that a single repository is manageable but large enough that implicit
  conventions are insufficient.
- CI/CD pipelines must be able to target individual modules without running the entire estate.

### Forces

- Monorepos centralize governance but risk scaling bottlenecks.
- Multi-repo setups isolate blast radius but fragment visibility.
- Terragrunt's `include` and `read_terragrunt_config` mechanics enable deep configuration layering
  but add cognitive overhead for newcomers.
- Registry-based module sourcing enforces versioning discipline but adds release ceremony overhead.
- Local monorepo sourcing enables atomic cross-module changes but requires discipline to avoid
  unintended coupling.

## Decision

We adopt a **single monorepo** with Terragrunt orchestration, organized around a **7-layer
configuration hierarchy** and **local monorepo module sourcing**.

### Repository Layout

```text
infra/
  terragrunt.hcl                          # Layer 1: Root
  live/
    aws/
      common.hcl                          # Layer 2: Cloud-wide defaults
      _base.hcl                           # Per-cloud base include (loads all layers)
      _versions.hcl                       # Module source pins
      {env}/
        env.hcl                           # Layer 3: Environment (account ID, env tags)
        {region}/
          region.hcl                      # Layer 4a: Region info
          network.hcl                     # Layer 4b: Network CIDRs
          {workload}/
            workload.hcl                  # Layer 5: Workload name, compliance tier
            {module}/
              terragrunt.hcl              # Layer 7: Final module overrides
    azure/
      ...                                 # Same hierarchy
    gcp/
      ...                                 # Same hierarchy
  modules/
    aws/
      organizations/
      state_bootstrap/
      networking/
      naming/
    azure/
      ...
    gcp/
      ...
```

### 7-Layer Configuration Hierarchy

Each layer has a well-defined scope and override semantics (later layers win for tags and inputs):

| Layer | File | Scope | Examples |
|-------|------|-------|---------|
| 1. Root | `infra/root.hcl` | Global | Remote state routing, provider generation, common tags, OpenTofu binary |
| 2. Cloud | `infra/live/{cloud}/common.hcl` | Cloud-wide | Project name, default workload, environment-to-account-ID safety map |
| 3. Environment | `infra/live/{cloud}/{env}/env.hcl` | Per-account | Account ID, environment name, data classification, env-specific tags |
| 4. Region | `infra/live/{cloud}/{env}/{region}/region.hcl` + `network.hcl` | Per-region | Region name/abbreviation, VPC CIDRs, region tags |
| 5. Workload | `infra/live/{cloud}/{env}/{region}/{workload}/workload.hcl` | Per-workload | Workload name, compliance tier, workload-specific tags |
| 6. Defaults | `infra/live/{cloud}/_envcommon/*.hcl` | Shared module defaults | Default input values reused across environments |
| 7. Module | `infra/live/{cloud}/{env}/{region}/{workload}/{module}/terragrunt.hcl` | Per-deployment | Final source reference, input overrides, dependencies |

### Per-Cloud Base Include (`_base.hcl`)

Each cloud has a `_base.hcl` that every module-level `terragrunt.hcl` includes. This file:

- Loads all configuration layers via `read_terragrunt_config` + `find_in_parent_folders`.
- Performs a flat merge of all layers into `all_vars` for ad-hoc lookups.
- Extracts commonly used scalars (`env`, `workload`, `compliance_tier`, `region`, `account_id`).
- Composes tags with explicit merge order: common -> environment -> region -> workload.
- Runs safety validations: directory path must match configured environment; account ID must match
  the expected value from the environment-account map.

### Module Sourcing: Local Monorepo

Module sources are pinned in `_versions.hcl` per cloud:

```hcl
module_source = {
  organizations   = "${local.source_base}/aws//organizations"
  state_bootstrap = "${local.source_base}/aws//state_bootstrap"
  networking      = "${local.source_base}/aws//networking"
  naming          = "${local.source_base}/aws//naming"
}
```

Modules are referenced by path from the repo root (`get_repo_root()`), not from a registry. This
means module changes and live configuration changes can be reviewed and merged atomically in a
single pull request.

### Cloud-Aware Remote State Routing

The root `terragrunt.hcl` detects the cloud provider from the directory path
(`split("/", path_relative_to_include())`) and routes state to the appropriate backend:

- **AWS modules** -> S3 + DynamoDB in the management account (<MGMT_ACCOUNT_ID>)
- **Azure/GCP modules** -> Azure Blob Storage with Azure AD authentication

This is a single conditional expression, not separate root configs per cloud.

## Consequences

### Positive

- **Single source of truth.** All infrastructure code, configuration, and module definitions live in
  one repository. Code review, CI status, and audit trails are unified.
- **Atomic changes.** A module refactor and the corresponding live configuration update ship in one
  PR. No cross-repo version coordination needed.
- **DRY configuration.** The 7-layer hierarchy eliminates per-module boilerplate. A new module
  deployment in an existing environment inherits region, account, tagging, and compliance settings
  automatically.
- **Safety rails.** The `_base.hcl` validation assertions catch environment/account mismatches
  before any resource is created, preventing accidental cross-account deployments.
- **Cloud isolation with shared patterns.** Each cloud has its own `_base.hcl`, `common.hcl`, and
  `_versions.hcl`, so cloud-specific concerns stay contained while the overall structure is
  consistent.
- **Selective execution.** Terragrunt's directory-based targeting means CI can run `terragrunt plan`
  on a single module without processing unrelated clouds or environments.

### Negative

- **Cognitive overhead.** New engineers must understand the 7-layer hierarchy, the `_base.hcl`
  mechanics, and Terragrunt's `include`/`expose`/`read_terragrunt_config` semantics before they can
  contribute effectively.
- **Monorepo scaling.** As the number of modules and environments grows, `terragrunt run-all` at
  the repo root becomes slow. This is mitigated by scoping runs to specific directories.
- **Tight coupling risk.** Local module sourcing means a breaking change to a module immediately
  affects all consumers. There is no version pinning buffer like a registry provides. This is
  mitigated by CI plan-all checks on PRs that touch modules.
- **No independent module versioning.** All consumers of a module always use the same (HEAD)
  version. Canary rollouts of module changes require feature flags or directory-level overrides
  rather than version pinning.

### Risks

- If the team grows significantly, monorepo merge contention could become a bottleneck. Mitigation:
  CODEOWNERS per cloud/environment directory.
- The `find_in_parent_folders` pattern assumes a strict directory hierarchy. Any deviation (e.g.,
  shared modules across clouds) requires explicit path overrides.
- OpenTofu compatibility must be validated when upgrading provider versions, since the root config
  generates provider blocks globally.

### What This Enables

- Adding a new AWS environment is a matter of creating an `env.hcl` with the account ID and
  replicating the region/workload/module directory structure.
- Adding a new cloud provider requires a new `_base.hcl`, `common.hcl`, `_versions.hcl`, and a
  remote state routing branch in the root `terragrunt.hcl`.
- Compliance auditors can trace any deployed resource to a specific directory path, PR, and merge
  commit in a single repository.
