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
| Resource organisation | "data sources first, dependency order"; a separate `locals.tf` | **Section-header banners** grouping resources in `main.tf`; locals live in `main.tf` |
| Version block file | `terraform.tf` | **`versions.tf`** — and only when the module uses a non-AWS provider (helm, kubernetes, etc.) |
| Provider blocks | `providers.tf` with `provider "aws" {}` | **None.** Modules declare *zero* provider blocks — providers are injected by Terragrunt (`root.hcl` / `_base.hcl`) |
| Version constraints | "use the latest major version" | Deliberate `>= X.0` ranges; CLI versions pinned canonically in `/.tool-versions` |
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
| `versions.tf` | The `terraform { required_version, required_providers }` block — **only if** the module needs a provider beyond `aws` (e.g. `helm`, `kubernetes`, `keycloak`) |

Do **not** create `providers.tf`, `terraform.tf`, or `locals.tf`. We don't split
providers out because modules never declare them (see below), and locals stay next to
the resources they serve, under the relevant section header in `main.tf`.

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
      version = ">= 5.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }
}
```

Note the binary is OpenTofu — the block is still spelled `terraform { ... }` because
OpenTofu reads it. Use deliberate floor ranges (`>= 5.0`), not "latest major" and not
exact pins; the actual CLI tool versions (`tofu`, `terragrunt`, etc.) are pinned
canonically in `/.tool-versions`, which is the single source of truth.

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

## Testing

Modules are tested with **Terratest (Go)**, not `.tftest.hcl`. Tests live in
`infra/tests/aws/<module>/` with fixtures in `fixtures/`, and must run against the
OpenTofu binary (`TerraformBinary: "tofu"` in the test options). Use plan-only tests for
modules that can't be safely applied/destroyed in CI. See CLAUDE.md → Testing Conventions.

## Review checklist

- [ ] `tofu fmt` clean; `terragrunt hcl fmt --check` clean; `tofu validate` passes
- [ ] Files: `main.tf` / `variables.tf` / `outputs.tf` (+ `versions.tf` only if a non-AWS provider is used); no `providers.tf` / `terraform.tf` / `locals.tf`
- [ ] No `provider "..." {}` block anywhere in the module
- [ ] Resources grouped under section-header banners in `main.tf` (or module small enough not to need them)
- [ ] Every variable has `type` + `description`; every output has `description`; sensitive values marked
- [ ] Descriptive snake_case singular resource names, excluding the type
- [ ] `for_each` for sets, `count` only for conditional creation
- [ ] No hardcoded secrets; AWS resources have encryption/public-access/logging defaults
- [ ] Provider version requirements expressed as deliberate floor ranges in `versions.tf`

---

*Adapted from HashiCorp's Terraform Style Guide skill (`hashicorp/agent-skills`),
licensed under MPL-2.0. Modifications © this project, retained under MPL-2.0.
Overridden for an OpenTofu + Terragrunt codebase.*
