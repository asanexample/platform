---
name: terragrunt-units
description: >-
  How to author and edit Terragrunt unit files (infra/live/aws/**/terragrunt.hcl) in this
  OpenTofu + Terragrunt platform repo. Use when adding a new unit, wiring a unit to a
  module, adding a dependency between units, editing inputs/provider generation, or
  touching the config hierarchy (root.hcl, common.hcl, env/region/network/workload .hcl,
  _base.hcl, _versions.hcl). It encodes the house conventions the formatter can't enforce:
  the include base+root pattern, sourcing modules via include.base.locals.module_source
  (never a hardcoded path), mandatory mock_outputs on every dependency, unit-level provider
  generation with the deployer role, the include.base.locals.* accessors, and the
  redesigned v1.x run --all commands. NOT for module .tf authoring (use terraform-style)
  or Kubernetes manifests.
---

# Authoring Terragrunt Units

This repo runs **OpenTofu (`tofu`) + Terragrunt v1.x** (the redesigned CLI). A *unit* is a
leaf `terragrunt.hcl` under `infra/live/aws/...` that wires one module into one environment.
This skill is grounded in the real files — the docs (CLAUDE.md) are known to be stale on
some paths, so the structure below is verified against `infra/live/aws/.../eks/terragrunt.hcl`,
`infra/root.hcl`, and `infra/live/aws/_base.hcl` / `_versions.hcl`.

> **Scope.** Unit files and the hierarchy layer files under `infra/live/`. For module
> `.tf` authoring use the **terraform-style** skill; this is about the Terragrunt wiring.

## The config hierarchy (real paths)

A unit inherits a stack of config layers, each `read_terragrunt_config`-loaded by `_base.hcl`:

```
infra/root.hcl                                   remote state (S3) + AWS provider generation + SOPS; terraform_binary = "tofu"
  └─ infra/live/aws/common.hcl                   org-wide defaults, loads SOPS secrets → account_ids/emails/SSO
      └─ infra/live/aws/<env>/env.hcl            environment + account_id (from secrets), env tags, feature toggles
          └─ <env>/<region>/region.hcl           region + region_abbv
          └─ <env>/<region>/network.hcl          vpc_cidr, azs, subnet tiers (empty for global units)
              └─ <env>/<region>/<workload>/workload.hcl   workload name, compliance_tier
                  └─ .../<unit>/terragrunt.hcl   the unit
infra/live/aws/_base.hcl                         loads + merges all layers, exposes include.base.locals.*
infra/live/aws/_versions.hcl                     module_source map + helm_versions (pinned)
```

Note `root.hcl` lives at **`infra/root.hcl`** (CLAUDE.md's diagram misplaces it under `live/aws/`).

## Anatomy of a unit `terragrunt.hcl`

Every unit starts with the same two includes — **`base`** (with `expose = true` so you can
read `include.base.locals.*`) and **`root`**:

```hcl
include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}
```

### Source the module via the registry — never hardcode a path

Module sources live in one place, `_versions.hcl`'s `module_source` map (so version/location
is single-sourced). A unit references the key, it does **not** write a relative path:

```hcl
terraform {
  source = include.base.locals.module_source.eks
}
```

To wire a *new* module, add it to `infra/live/aws/_versions.hcl`'s `module_source` map
(`<key> = "${local.source_base}/aws//<module-dir>"` — note the `//` subdir separator;
`source_base` is `${get_repo_root()}/infra/modules`), then reference `module_source.<key>`.

### Dependencies — every one needs `mock_outputs`

A `dependency` pulls another unit's outputs by relative `config_path`. **Every dependency
must declare `mock_outputs` plus the exact allowed-commands list** — without it, `destroy`
and `plan` break once an upstream unit's state is gone (teardown destroys upstreams first):

```hcl
dependency "networking" {
  config_path = "../networking"

  mock_outputs = {
    vpc_id                = "vpc-mock"
    subnet_ids            = {}
    eks_security_group_id = "sg-mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}
```

- `mock_outputs` shape must match the real outputs you reference; values are placeholders
  (e.g. `arn:aws:iam::000000000000:role/...`).
- `apply` is deliberately **not** in the allowed list — apply needs real outputs.
- For a pure ordering edge (no outputs consumed), use `mock_outputs = {}` with the same
  allowed-commands list.
- Cross-account/cross-env deps use a longer relative path, e.g. `config_path = "../../../../preprod/us-east-1/platform/iam-roles"`.

### Inputs — pull from `include.base.locals.*` and dependency outputs

```hcl
inputs = {
  create       = true
  cluster_name = "${include.base.locals.env}-${include.base.locals.region_abbv}-eks"
  tags         = include.base.locals.tags

  subnet_ids = [
    for name, id in dependency.networking.outputs.subnet_ids : id if can(regex("kubernetes$", name))
  ]
}
```

### Provider generation — at the unit, with the deployer role

Modules declare provider *requirements* but never configure providers (terraform-style
covers this). The AWS provider is generated by `root.hcl`. **Helm/Kubernetes/Keycloak
providers are generated by the unit** via a `generate` block, with exec auth assuming
`PlatformDeployer`:

```hcl
generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")
        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
        }
      }
    }
  EOF
}
```

### Unit-level `locals` for computed inputs

Units may compute inputs from the filesystem/git (e.g. deriving teams from `gitops/teams/`)
in a `locals` block before `inputs`; reference repo paths with `${get_repo_root()}/...`.
Before/after hooks (e.g. a port-forward for in-cluster config) go *inside* `terraform { }`
with `run_on_error = true` on cleanup hooks.

## `include.base.locals.*` — the accessors you'll use

| Accessor | What it is |
|---|---|
| `account_id` | current env's AWS account ID (resolved from SOPS secrets) |
| `account_ids["<env>"]` | any env's account ID (for cross-account deps) |
| `account_emails["<env>"]`, `admin_email` | contact emails from secrets |
| `env`, `region`, `region_abbv`, `workload`, `compliance_tier` | hierarchy scalars |
| `deployer_role_arn` | `arn:aws:iam::<account_id>:role/PlatformDeployer` (provider exec auth) |
| `tags` | merged tag map (common→env→region→workload) |
| `module_source.<key>` | module path from `_versions.hcl` |
| `helm_versions.<chart>` | pinned chart version from `_versions.hcl` |
| `all_vars.<x>` | flat merge of all layers for ad-hoc lookups (e.g. `all_vars.subnets`, `all_vars.address_space`) |

## Secrets (SOPS)

Sensitive values (account IDs, emails, SSO URLs) are SOPS-encrypted and committed at
`infra/live/aws/secrets.enc.yaml`, decrypted at parse time (ADR-066). Reach them through the
exposed accessors above — never inline a secret in a unit. The greenfield escape
`TG_SOPS_BOOTSTRAP=1` falls back to a gitignored plaintext `infra/live/aws/secrets.hcl`
(only before the KMS key exists).

## Commands (verified, redesigned v1.x CLI)

```bash
# Single unit (from its directory) — provider assumes PlatformDeployer via root.hcl
terragrunt plan
terragrunt apply

# Whole environment DAG (from an env's platform dir)
terragrunt run --all apply

# Destroy (reverse DAG)
terragrunt run --all destroy --filter-allow-destroy -- -auto-approve

# Format the HCL (NOT `hclfmt`)
terragrunt hcl fmt --check
```

It is **`terragrunt run --all <cmd>`**, not the legacy `run-all`. In `destroy`, `--` separates
Terragrunt flags from the `-auto-approve` passed through to OpenTofu. For full
bootstrap/teardown with ordering + dry-run, prefer `platctl` (built to `./bin/platctl` via
`make build-platctl`). CI uses `terragrunt apply -auto-approve -no-color -input=false`.

## Review checklist

- [ ] `include "base"` (with `expose = true`) **and** `include "root"` present
- [ ] Module sourced via `include.base.locals.module_source.<key>` — no hardcoded path; new modules added to `_versions.hcl`
- [ ] Every `dependency` has `mock_outputs` + `mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]`
- [ ] Inputs pull from `include.base.locals.*` / dependency outputs; no inlined secrets or account IDs
- [ ] Helm/K8s/Keycloak providers generated at the unit with `deployer_role_arn` exec auth (if the module needs them)
- [ ] `terragrunt hcl fmt --check` clean

## References

- `infra/root.hcl`, `infra/live/aws/{common,_base,_versions}.hcl` — the real hierarchy
- `infra/live/aws/platform/us-east-1/platform/eks/terragrunt.hcl` — a canonical multi-dependency unit
- CLAUDE.md → "Terragrunt Config Hierarchy" / "Deployment Ordering" (cross-check against the real files — some paths are stale)
