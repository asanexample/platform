# ADR-002: AWS State Storage in S3 with Cloud-Aware Routing

**Date:** 2025-05-15

**Status:** Accepted

## Context

Infrastructure-as-code tools require a persistent state backend to track the mapping between
declared resources and their real-world counterparts. The choice of state backend has implications
for security, reliability, access control, and operational complexity.

### The Multi-Cloud State Problem

The platform is built multi-cloud-ready but **AWS-first** (Azure/GCP deferred — see
[ADR-001](001-multi-cloud-terragrunt-structure.md)). The design question that informs the state backend:
should each cloud's state live in its own cloud-native backend, or share one? Storing one cloud's state
in another's backend (e.g. AWS state in Azure Blob) doubles the authentication surface and couples the
clouds' availability. We chose **per-cloud, cloud-native backends** — so AWS state lives in AWS-native
S3, and a future Azure/GCP backend slots in independently.

### Constraints

- **AWS Organizations** is being created from the management account (<MGMT_ACCOUNT_ID>). The management
  account is the natural home for centralized state storage.
- **Cross-cloud authentication complexity.** Storing one cloud's state in another's backend forces
  every pipeline and workstation to authenticate to both clouds — doubling the authentication surface.
- **State backend performance.** S3 in `us-east-1` gives AWS operations native, low-latency state
  access rather than cross-cloud HTTPS calls.
- **Blast radius isolation.** One cloud's storage outage should not block another cloud's
  infrastructure operations.
- **Additive future clouds.** A second cloud's backend (Azure/GCP, when they land) must slot in
  without disrupting the AWS backend.

### The Bootstrap Chicken-and-Egg Problem

Terraform state backends must exist before any Terraform module can use them. But if the state
backend (S3 bucket, DynamoDB lock table) is itself managed by Terraform, its own state cannot be
stored in the backend it has not yet created. This is the classic "who creates the state bucket"
problem.

### Forces

- Terragrunt has a built-in `remote_state` auto-creation feature that can create S3 buckets and
  DynamoDB tables automatically. However, auto-created resources are not tracked in state, cannot be
  tagged consistently, and cannot be customized (e.g., KMS encryption, bucket key enablement).
- A dedicated bootstrap module with local state solves the chicken-and-egg but introduces a special
  case in the deployment workflow.
- Shared state backends across clouds simplify the mental model but create cross-cloud dependencies.
- Per-cloud backends add operational overhead but improve isolation.

## Decision

### Per-Cloud State Backends

AWS infrastructure state is stored in **S3 with DynamoDB locking** in the AWS management account.
Azure and GCP state continues to use Azure Blob Storage. Each cloud's state lives in its own
cloud-native backend.

### Cloud-Aware-Ready Routing in `root.hcl`

`root.hcl` retains **path-based cloud detection** so per-cloud state routing can be re-activated when a
second cloud lands. Today only AWS is deployed, so the `remote_state` block resolves unconditionally to
S3; the `_cloud` local is computed and kept *"for future multi-cloud"* but does not yet branch the
backend:

```hcl
locals {
  # Detect cloud provider from directory path (kept for future multi-cloud)
  _path_parts_cloud = split("/", path_relative_to_include())
  _cloud            = try(local._path_parts_cloud[1], "aws")
  _secrets          = read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl")
}

remote_state {
  backend = "s3"
  config = {
    bucket         = local._secrets.locals.state_bucket    # tfstate-mgmt-<acct>, from secrets.hcl
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
    role_arn       = local._secrets.locals.state_role_arn  # TerraformStateAccess (ADR-007)
  }
}
```

When Azure/GCP return, the backend becomes a `local._cloud == "aws" ? "s3" : "azurerm"` conditional
again. The bucket name and the state-access role ARN come from the gitignored `secrets.hcl`.

### S3 Backend Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| Bucket | `tfstate-mgmt-<acct>` (from `secrets.hcl`) | Account-ID suffix prevents global name collisions and makes ownership obvious |
| Region | `us-east-1` | Primary AWS region; Organizations API endpoint is us-east-1 |
| Encryption | `true`, SSE-KMS (AWS-managed key) | State files may contain sensitive resource attributes |
| DynamoDB table | `terraform-locks` | Prevents concurrent state modifications; PAY_PER_REQUEST billing |
| State key | `{path_relative_to_include}/terraform.tfstate` | Directory structure maps 1:1 to state keys, making state files discoverable |
| Access role | `TerraformStateAccess` (`role_arn` from `secrets.hcl`) | Dedicated cross-account role scoped to the state bucket + lock table ([ADR-007](007-iam-role-model.md)) |

### Bootstrap Module for Chicken-and-Egg Resolution

A dedicated `state_bootstrap` module (`infra/modules/aws/state_bootstrap/`) creates the S3 bucket
and DynamoDB lock table. This module:

1. **Uses a local backend.** Its `terragrunt.hcl` explicitly overrides the root `remote_state`
   block to use a local file backend, breaking the circular dependency.

2. **Is separate from the Organizations module.** The state bucket must exist before the
   Organizations module (or any other module) can run. Keeping them separate ensures independent
   lifecycles and clear deploy ordering.

3. **Creates hardened resources.** Unlike Terragrunt's auto-create feature, the bootstrap module
   applies:
   - S3 bucket versioning (enabled) for state recovery
   - KMS server-side encryption with bucket key enabled
   - Full public access block (all four settings)
   - DynamoDB PAY_PER_REQUEST billing to avoid capacity provisioning

4. **Local state for the first apply, then migrated to S3.** The local `terraform.tfstate` (gitignored)
   is transient — once the bucket exists, the bootstrap's backend is migrated to S3 so it stores state
   in the bucket it created, just like every other module (details + recovery in
   [ADR-006](006-state-bootstrap-pattern.md)).

### Why Not Terragrunt Auto-Create

Terragrunt's `remote_state` block supports automatic bucket/table creation. We chose not to use it
because:

- **No state tracking.** Auto-created resources are not in any Terraform state file. They cannot be
  modified, tagged, or destroyed through IaC.
- **Limited configuration.** Auto-create does not support KMS bucket keys, custom encryption
  configurations, or fine-grained public access block settings.
- **Invisible drift.** If someone manually modifies the auto-created bucket, there is no drift
  detection mechanism.
- **Audit gap.** Compliance requires that all infrastructure be code-managed. An auto-created bucket
  is a gap in the audit trail.

## Consequences

### Positive

- **Cloud isolation.** An Azure outage does not affect AWS state operations. Each cloud's
  infrastructure can be planned, applied, and recovered independently.
- **Simplified authentication.** AWS pipelines only need AWS credentials. No cross-cloud
  authentication is required for state access.
- **Discoverable state.** The S3 key structure mirrors the directory hierarchy. Finding the state
  for any module is trivial: look at its path relative to the repo root.
- **Fully managed bootstrap.** The state bucket and lock table are tracked in IaC with proper
  encryption, versioning, and access controls. Drift is detectable.
- **Single routing logic.** Cloud detection lives in one place in `root.hcl`; re-introducing a second
  cloud's backend is one conditional branch, not a separate root config per cloud.

### Negative

- **Per-cloud backends to operate (when multi-cloud).** Today there is one backend (S3); when
  Azure/GCP return, each cloud's backend has its own backup, retention, and access policies to manage.
- **Bootstrap ceremony.** New AWS accounts require running the `state_bootstrap` module first with
  local state before any other module can be deployed. This is an extra step that must be documented
  and enforced.
- **Bootstrap special-case (first apply only).** The bootstrap's *first* apply uses local state before
  migrating to S3 — an exception to the normal workflow that must be documented (see ADR-006). After
  migration it is an ordinary S3-backed module.
- **Path coupling.** The cloud detection logic depends on the directory structure
  (`live/aws/...`). Reorganizing the directory hierarchy would break state routing.

### Risks

- If the management account (<MGMT_ACCOUNT_ID>) is compromised, all AWS state files are exposed.
  Mitigation: the management account should have the strictest access controls in the organization.
- S3 bucket deletion (accidental or malicious) would lose all AWS state. Mitigation: bucket
  versioning is enabled; MFA delete should be configured as a follow-up.
- The DynamoDB table uses PAY_PER_REQUEST, which is cost-effective at low scale but could become
  expensive under pathological lock contention. This is extremely unlikely for IaC workloads.

### Deploy Order

The bootstrap creates a hard dependency ordering for initial AWS setup:

```text
1. state_bootstrap  (local state)  -> Creates S3 bucket + DynamoDB table
2. organizations    (S3 state)     -> Creates org, OUs, accounts, SCPs
3. everything else  (S3 state)     -> Networking, compute, etc.
```

This ordering only matters for initial bootstrap. After the first deployment, all modules
(including state_bootstrap, should it need modification) can be operated independently.
