# ADR-002: AWS State Storage in S3 with Cloud-Aware Routing

**Date:** 2025-05-15

**Status:** Accepted

## Context

Infrastructure-as-code tools require a persistent state backend to track the mapping between
declared resources and their real-world counterparts. The choice of state backend has implications
for security, reliability, access control, and operational complexity.

### The Multi-Cloud State Problem

This repository manages infrastructure across AWS, Azure, and GCP. The existing Azure environment
uses Azure Blob Storage for Terraform state, authenticated via Azure AD. When the AWS buildout
began, the team faced a fundamental question: should AWS infrastructure state live alongside Azure
state in the existing Azure Blob Storage backend, or should each cloud's state live in its own
cloud-native backend?

### Constraints

- **AWS Organizations** is being created from the management account (<MGMT_ACCOUNT_ID>). The management
  account is the natural home for centralized state storage.
- **Cross-cloud authentication complexity.** Storing AWS state in Azure Blob Storage means every AWS
  CI/CD pipeline and developer workstation must authenticate to both AWS (for resource provisioning)
  and Azure (for state operations). This doubles the authentication surface.
- **State backend performance.** S3 in `us-east-1` provides lower latency for AWS operations than
  cross-cloud HTTPS calls to Azure Blob Storage in `eastus`.
- **Blast radius isolation.** An Azure outage should not block AWS infrastructure operations and
  vice versa.
- **Existing Azure state** must not be disrupted. The Azure backend (subscription
  `9dc5edc4-8c4e-41a1-a4f8-2183c4e91954`, storage account `tfstatemulticloud`) is already in
  production.

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

### Cloud-Aware Routing in Root `root.hcl`

The root `root.hcl` uses **path-based detection** to route state to the correct backend:

```hcl
locals {
  _path_parts_cloud = split("/", path_relative_to_include())
  _cloud            = try(local._path_parts_cloud[1], "azure")
}

remote_state {
  backend = local._cloud == "aws" ? "s3" : "azurerm"
  config = local._cloud == "aws" ? {
    bucket         = "tfstate-mgmt-<MGMT_ACCOUNT_ID>"
    key            = "${path_relative_to_include()}/terraform.tfstate"
    region         = "us-east-1"
    encrypt        = true
    dynamodb_table = "terraform-locks"
  } : {
    # Azure Blob Storage config...
  }
}
```

The detection logic splits the `path_relative_to_include()` on `/` and checks whether element `[1]`
(the cloud directory) is `"aws"`. Any module under `infra/live/aws/...` gets S3; everything else
defaults to Azure Blob Storage.

### S3 Backend Configuration

| Setting | Value | Rationale |
|---------|-------|-----------|
| Bucket | `tfstate-mgmt-<MGMT_ACCOUNT_ID>` | Account ID suffix prevents global name collisions and makes ownership obvious |
| Region | `us-east-1` | Primary AWS region; colocated with Organizations (global service, but API endpoint is us-east-1) |
| Encryption | `true` (AES-256/KMS) | Required for compliance; state files may contain sensitive resource attributes |
| DynamoDB table | `terraform-locks` | Prevents concurrent state modifications; PAY_PER_REQUEST billing |
| State key | `{path_relative_to_include}/terraform.tfstate` | Directory structure maps 1:1 to state keys, making state files discoverable |

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

4. **Commits `terraform.tfstate` to the repository.** Since this module uses local state, the state
   file is committed to the repo at the module's directory. This is safe because the state only
   contains metadata about an S3 bucket and a DynamoDB table -- no secrets, no sensitive attributes.

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
- **Single routing logic.** The path-based cloud detection in root `root.hcl` is a single
  conditional expression. Adding a new cloud requires one additional branch.

### Negative

- **Two state backends to operate.** The team must monitor and maintain both the S3 backend and the
  Azure Blob Storage backend. Backup, retention, and access policies must be managed separately.
- **Bootstrap ceremony.** New AWS accounts require running the `state_bootstrap` module first with
  local state before any other module can be deployed. This is an extra step that must be documented
  and enforced.
- **Local state file in repo.** The bootstrap module's `terraform.tfstate` is committed to the
  repository. While safe for this specific case (no secrets), it is an exception to the general rule
  of "never commit state files" and could confuse new contributors.
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

```
1. state_bootstrap  (local state)  -> Creates S3 bucket + DynamoDB table
2. organizations    (S3 state)     -> Creates org, OUs, accounts, SCPs
3. everything else  (S3 state)     -> Networking, compute, etc.
```

This ordering only matters for initial bootstrap. After the first deployment, all modules
(including state_bootstrap, should it need modification) can be operated independently.
