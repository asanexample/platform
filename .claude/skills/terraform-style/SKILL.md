---
name: terraform-style
description: >-
  House style for authoring OpenTofu/Terraform HCL in this repo's shared modules under
  infra/modules/. Use when writing, editing, scaffolding, refactoring, or reviewing a
  module's .tf files — adding or changing variables/outputs, declaring provider version
  requirements in versions.tf, organizing resources in main.tf, converting count to
  for_each, or stubbing a brand-new module — so code follows the repo's house conventions
  (section-header layout, no provider blocks inside modules, version-range pinning,
  naming, secret handling) rather than the generic Terraform defaults that tofu fmt and
  terragrunt hcl fmt can't catch. Consult it even for a small module edit. NOT for
  Terragrunt unit files under infra/live/ (terragrunt.hcl, root.hcl provider config),
  Kubernetes/Kyverno manifests, CI workflows, or ArgoCD/deployment troubleshooting.
---

# Terraform / OpenTofu House Style

Adapted from HashiCorp's official Terraform Style Guide for *this* repository, which
runs **OpenTofu (`tofu`) + Terragrunt**, not vanilla Terraform/HCP. We follow
HashiCorp's guidance wherever it doesn't conflict with our toolchain — the sections
below call out the deliberate overrides. When in doubt and this skill is silent,
defer to <https://developer.hashicorp.com/terraform/language/style>.

> **Scope.** This is for **shared modules** under `infra/modules/`. Terragrunt unit
> files (`terragrunt.hcl`, `*.hcl` under `infra/live/`) follow Terragrunt conventions,
> not this guide — `terragrunt hcl fmt` handles their formatting.

## The overrides at a glance

These are the points where we *intentionally* diverge from the upstream HashiCorp
guide. Everything else (naming, typed variables, described outputs, `for_each` over
`count`, sensitive marking) matches upstream — see below.

| Topic | Generic Terraform guidance | **This repo** |
|---|---|---|
| Resource organisation | "data sources first, dependency order"; a separate `locals.tf` | **Section-header banners** grouping resources in `main.tf`; locals live in `main.tf` — until a module gets big, when the banner sections become per-concern `.tf` files (see below) |
| Version block file | `terraform.tf` | **`versions.tf`** — **every** module ships one (pins `required_version` + the `aws` provider); a non-AWS provider just adds a `required_providers` entry |
| Provider blocks | `providers.tf` with `provider "aws" {}` | **None.** Modules declare *zero* provider blocks — providers are injected by Terragrunt (`root.hcl` / `_base.hcl`) |
| Version constraints | "use the latest major version" | Pessimistic `~> MAJOR.0` constraints (aws is on `~> 6.0`); CLI versions pinned canonically in `/.tool-versions` |
| Format / validate | `terraform fmt` / `terraform validate` | **`tofu fmt`**, `tofu validate`, `terragrunt hcl fmt` |
| Module tests | `.tftest.hcl` | **Terratest (Go)** in `infra/tests/aws/<module>/` |
| Secrets | inline / tfvars | config secrets via **SOPS+KMS**; workload hardening enforced by **Kyverno** at admission |

## File organisation

A module is three files, plus a fourth when needed:

| File | Purpose |
|------|---------|
| `main.tf` | All resources, data sources, and `locals`, grouped under section headers |
| `variables.tf` | Input variable declarations |
| `outputs.tf` | Output declarations |
| `versions.tf` | The `terraform { required_version, required_providers }` block — **every module has one** (pins `required_version` + the `aws` provider); modules that need a provider beyond `aws` (e.g. `helm`, `kubernetes`, `keycloak`) add it to `required_providers` |

Do **not** create `providers.tf` or `terraform.tf`. We don't split providers out
because modules never declare them (see below).

For a **small or mid-sized module**, keep everything in `main.tf` — locals included,
next to the resources they serve under the relevant section header. Don't create
`locals.tf` or per-concern files just to have them.

### Splitting a large `main.tf` into per-concern files

Once a `main.tf` clears **~500 lines** (or has a cleanly separable subsystem — e.g.
`observability-opencost`'s `budget-enforcer.tf` / `true-cost-exporter.tf`), promote its
banner sections to their own `.tf` files rather than scrolling one wall. OpenTofu reads
every `*.tf` in a module dir as one config, so this is **purely organisational** — a
resource's address is `type.name`, not file-scoped, so moving a block between files
changes nothing in state (**no `moved` blocks, a clean 0-change plan**).

Rules for the split:

- **Split along the existing `# ---` banner seams** — one cohesive concern per file
  (`networkpolicy.tf`, `iam.tf`, `s3.tf`, `dashboards.tf`, `alerting.tf`, …). The seams
  are already there; the split is mechanical.
- **`main.tf` stays the anchor** — keep the primary resource (the `helm_release`, the
  `aws_eks_cluster`, …) and the namespace/scaffolding there, so `main.tf` still answers
  "what does this deploy". Peel off the *satellite* resources (secrets, netpol,
  configmaps, IAM).
- **`locals.tf` is allowed here** — when the computed inputs (helm values, config maps)
  are a big block, move the whole `locals {}` block into `locals.tf` verbatim. This is
  the one case where `locals.tf` is fine.
- Each file still opens with its banner header; keep `variables.tf` / `outputs.tf` /
  `versions.tf` as the other three files.
- Verify it's a true no-op: `tofu fmt -check` clean + `tofu validate` passes + the diff
  is pure block-moves (no content change). Reference split: the `observability` and
  `observability-mimir` modules.

## Section headers in `main.tf`

This is the single biggest divergence from generic Terraform and the thing `tofu fmt`
can't do for you. Instead of ordering by "data sources, then resources in dependency
order," we group related resources under banner comments so a long `main.tf` reads as
labelled sections. Use this exact banner shape:

```hcl
# ---------------------------------------------------------------------------
# Section Name
# ---------------------------------------------------------------------------
```

Group by logical concern — e.g. `IAM`, `KMS`, `EKS Cluster`, `OIDC Provider (for IRSA)`,
`Access Entries`. A short prose comment under a header to explain a non-obvious choice
is welcome. Small modules with only a few resources don't need headers at all — don't
manufacture sections for the sake of it.

```hcl
# ---------------------------------------------------------------------------
# KMS — Envelope Encryption for Secrets
# ---------------------------------------------------------------------------

resource "aws_kms_key" "secrets" {
  description             = "EKS secrets envelope encryption"
  enable_key_rotation     = true
  deletion_window_in_days = 7
}

# ---------------------------------------------------------------------------
# EKS Cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  # ...
}
```

## No provider blocks in modules

Modules must contain **zero** `provider "..." {}` blocks. Provider configuration —
including credentials (`assume_role` to `PlatformDeployer`), region, and `default_tags`
— is generated and injected by Terragrunt at the root (`root.hcl` / `_base.hcl`).
Declaring a provider inside a module breaks that injection and the `run --all` graph.

`versions.tf` declares the *requirement* (which providers and what versions), never the
*configuration*:

```hcl
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
```

Note the binary is OpenTofu — the block is still spelled `terraform { ... }` because
OpenTofu reads it. Use pessimistic `~> MAJOR.0` constraints (the `aws` provider is on
`~> 6.0`), not "latest major" and not exact pins; the actual CLI tool versions (`tofu`,
`terragrunt`, etc.) are pinned canonically in `/.tool-versions`, which is the single
source of truth.

## Naming (matches HashiCorp)

- Lowercase with underscores for all identifiers.
- Resource names are **descriptive nouns that exclude the resource type** and are
  **singular** — `aws_instance.web_api`, not `aws_instance.web_apis` or
  `aws_instance.web-api-instance`.
- Default to `this` or `main` when there's a single instance and a more specific name
  would just be noise (e.g. `aws_eks_cluster.this`).
- Variables and outputs: descriptive, no redundant prefixes (`name`, not `var_name`).

```hcl
# Bad
resource "aws_instance" "webAPI-aws-instance" {}
resource "aws_instance" "web_apis" {}

# Good
resource "aws_instance" "web_api" {}
resource "aws_eks_cluster" "this" {}
```

## Variables and outputs (matches HashiCorp)

Every variable declares `type` and `description`. Add a `validation` block when there's
a real invariant worth catching at plan time — don't add hollow ones.

```hcl
variable "instance_type" {
  description = "EC2 instance type for the node group"
  type        = string
  default     = "t3.large"
}

variable "vpc_cidr" {
  description = "CIDR block for the VPC"
  type        = string

  validation {
    condition     = can(cidrhost(var.vpc_cidr, 0))
    error_message = "vpc_cidr must be a valid IPv4 CIDR block."
  }
}
```

Every output declares a `description`. Mark sensitive outputs `sensitive = true` so they
don't leak into plan logs.

## for_each over count (matches HashiCorp)

Prefer `for_each` for sets of similar resources — it keys instances by a stable name, so
adding or removing one doesn't churn the others in state. Reserve `count` for
**conditional creation** (`count = var.enabled ? 1 : 0`).

```hcl
# Multiple similar resources → for_each, keyed by a stable name
resource "aws_subnet" "public" {
  for_each          = toset(var.availability_zones)
  availability_zone = each.value
  # ...
}

# Conditional creation → count
resource "aws_cloudwatch_metric_alarm" "cpu" {
  count = var.enable_monitoring ? 1 : 0
  # ...
}
```

## Formatting (matches HashiCorp)

- Two spaces per nesting level, no tabs.
- Align consecutive `=` signs within a block.
- Within a resource: meta-arguments (`count`/`for_each`/`provider`) first, then
  arguments, then nested blocks, then `lifecycle` last.

Run before committing — the pre-commit hook (`.githooks/pre-commit`) enforces these:

```bash
tofu fmt -check -recursive infra/modules/
terragrunt hcl fmt --check
tofu validate
```

## Secrets and security

Most workload-level hardening (encryption, non-root, dropped capabilities, image
provenance) is enforced for *deployed environments* by Kyverno at admission and by SOPS
for config secrets — see CLAUDE.md and `docs/architecture/`. At the **module** authoring
level, the relevant habits are:

- Never hardcode credentials or secrets in `.tf`. Sensitive config lives SOPS-encrypted
  in `infra/live/aws/secrets.enc.yaml` and is surfaced through Terragrunt, not baked into
  modules.
- For AWS resource modules, enable security defaults at the source: encryption at rest
  (KMS), `block_public_*` on S3 buckets, least-privilege IAM, and logging.
- Prefer provider-native secret management (e.g. `manage_master_user_password = true` on
  RDS/Aurora) over passing a secret through a variable into state.
- When a provider supports **write-only attributes** + `ephemeral` resources (OpenTofu
  ≥ 1.11), use them for sensitive values so they never persist to state.

```hcl
# Good — engine-managed master credential, never in state
resource "aws_rds_cluster" "this" {
  cluster_identifier          = "backstage"
  manage_master_user_password = true
  master_username             = "backstage"
}
```

## Destroy-time teardown-drain `null_resource`s

Several modules (`crossplane`, `backstage`, `keycloak`, `platform-directory`, `tailscale`,
`observability`) need a destroy-time `null_resource` that force-drains a stateful
workload (CNPG Cluster, Crossplane CRs, Connector/ProxyClass, …) before the namespace/
release deletes — an operator-managed finalizer otherwise hangs the real teardown. If
you're authoring a new one of these, two rules, both learned the hard way (#1077/#1081):

1. **Never bake the script's absolute path into `triggers`.** `triggers` is the *only*
   thing that drives a `null_resource` replace, and a destroy-time provisioner can only
   reference `self`/`count.index`/`each.key` (verified — OpenTofu rejects a direct
   `var.x` reference there). So resolve the script path **inside the provisioner
   command itself**, at shell-execution time, via `git rev-parse --show-toplevel` — not
   as a Terraform-computed value passed through `triggers`. Baking an absolute path into
   `triggers` makes the resource worktree-path-sensitive: a worktree's different path
   looks like a changed trigger, forcing a replace that fires the destroy provisioner
   for real outside of any actual teardown.

   ```hcl
   resource "null_resource" "namespace_drain" {
     count = local.create && var.finalizer_clear_script != "" ? 1 : 0

     triggers = {
       cluster   = var.cluster_name
       region    = var.region
       role_arn  = var.deployer_role_arn
       namespace = var.namespace
       refs      = "clusters.postgresql.cnpg.io pods"
     }

     provisioner "local-exec" {
       when    = destroy
       command = "bash \"$(git rev-parse --show-toplevel)/scripts/k8s-finalizer-clear.sh\" --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} ${self.triggers.namespace} ${self.triggers.refs}"
     }
   }
   ```

   `finalizer_clear_script` is only checked for non-emptiness (`!= ""` gates `count`) —
   its value is never read for the path itself. It stays a path-shaped string purely
   for unit-wiring compatibility (units pass `get_repo_root()`).

2. **Removing a `triggers` key from an *existing* resource needs `lifecycle.ignore_changes`.**
   If a resource already has state with a key that your change removes from `triggers`
   (e.g. migrating an old `script = var.finalizer_clear_script` trigger away per rule 1
   above), that removal alone forces a replace — which fires the destroy provisioner
   for real on whatever you next apply, not just on an actual teardown. Pin the
   soon-to-be-orphaned key so its removal from config doesn't register as a diff:

   ```hcl
   lifecycle {
     ignore_changes = [triggers["script"]]
   }
   ```

   A genuine change to any *other* trigger key still forces a replace as intended —
   `ignore_changes` only pins the one named key. Not needed when authoring a brand-new
   resource from scratch (nothing in state to orphan).

## Testing

Modules are tested with **Terratest (Go)**, not `.tftest.hcl`. Tests live in
`infra/tests/aws/<module>/` with fixtures in `fixtures/`, and must run against the
OpenTofu binary (`TerraformBinary: "tofu"` in the test options). Use plan-only tests for
modules that can't be safely applied/destroyed in CI. See CLAUDE.md → Testing Conventions.

## Review checklist

- [ ] `tofu fmt` clean; `terragrunt hcl fmt --check` clean; `tofu validate` passes
- [ ] Files: `main.tf` / `variables.tf` / `outputs.tf` / `versions.tf` (every module has `versions.tf`); no `providers.tf` / `terraform.tf` / `locals.tf`
- [ ] No `provider "..." {}` block anywhere in the module
- [ ] Resources grouped under section-header banners in `main.tf` (or module small enough not to need them)
- [ ] Every variable has `type` + `description`; every output has `description`; sensitive values marked
- [ ] Descriptive snake_case singular resource names, excluding the type
- [ ] `for_each` for sets, `count` only for conditional creation
- [ ] No hardcoded secrets; AWS resources have encryption/public-access/logging defaults
- [ ] Provider version requirements expressed as pessimistic `~> MAJOR.0` constraints in `versions.tf` (`aws` is `~> 6.0`)
- [ ] Any destroy-time teardown-drain `null_resource` resolves its script path via `git rev-parse --show-toplevel` in the provisioner command, never bakes an absolute path into `triggers`; removing an existing trigger key gets `lifecycle.ignore_changes`

---

*Adapted from HashiCorp's Terraform Style Guide skill (`hashicorp/agent-skills`),
licensed under MPL-2.0. Modifications © this project, retained under MPL-2.0.
Overridden for an OpenTofu + Terragrunt codebase.*
