# ADR-006: State Bootstrap Pattern

**Date:** 2025-05-15

**Status:** Accepted

## Context

Every Terraform/OpenTofu deployment requires a state backend to persist the mapping between
declared resources and real-world infrastructure. For AWS, the standard backend is S3 (for state
storage) with DynamoDB (for locking). But these backend resources must themselves exist before any
Terraform module can use them, creating a classic chicken-and-egg problem:

> You cannot use S3 remote state to create the S3 bucket that stores your remote state.

This problem is universal in Terraform deployments and has several common solutions, each with
trade-offs.

### Common Approaches

**1. Manual creation.** Create the S3 bucket and DynamoDB table via the AWS Console or CLI.

- Pros: Simple, no tooling dependency.
- Cons: Not tracked in IaC, no drift detection, no code review, audit gap. Violates the principle
  that all infrastructure should be code-managed.

**2. Terragrunt auto-create.** Terragrunt's `remote_state` block can automatically create the S3
bucket and DynamoDB table if they don't exist.

- Pros: Zero ceremony, works out of the box.
- Cons: Resources are not tracked in any Terraform state. Cannot be tagged, customized (encryption
  settings, public access blocks), or destroyed through IaC. Creates an audit gap. No versioning
  or encryption configuration beyond Terragrunt's defaults.

**3. CloudFormation bootstrap.** Use a CloudFormation stack to create the backend resources.

- Pros: Tracked in CloudFormation state, supports all S3/DynamoDB configurations.
- Cons: Introduces a second IaC tool. The bootstrap stack must be maintained separately and is
  outside the Terragrunt workflow.

**4. Dedicated Terraform module with local state.** Create a small Terraform module that manages
the S3 bucket and DynamoDB table, using a local file backend for its own state.

- Pros: Fully tracked in IaC, supports all configurations, uses the same tooling as everything
  else. Its state is local-only (gitignored); because the bucket/table have deterministic names, a
  lost state file is recovered by `import`.
- Cons: Introduces a special case (local state in a repo that otherwise uses remote state).
  Requires a documented deploy order.

### Constraints

- The organization requires all infrastructure to be managed through IaC for audit compliance
  (SOC 2, NIST 800-53).
- The state bucket must have S3 versioning enabled (for state recovery), KMS encryption with
  bucket keys (for cost-effective encryption), and a full public access block (for security).
- The DynamoDB table must exist for state locking to prevent concurrent modifications.
- The bootstrap must be idempotent: running it multiple times should not fail or create duplicate
  resources.
- The bootstrap module must be separate from the Organizations module because they have different
  lifecycles and the state bucket must exist before the Organizations module can run.

### Forces

- The desire for "everything in IaC" conflicts with the bootstrapping chicken-and-egg.
- State files are kept out of remote backends *and* out of Git (the blanket `*.tfstate` gitignore), so
  the bootstrap's state lives only on the operator's disk — recovery leans on the module's
  deterministic resource names + `import` rather than on a stored copy.
- The bootstrap module's lifecycle is fundamentally different from all other modules: it is run
  once (or very rarely), while other modules are applied regularly.
- Coupling the state bucket creation with the Organizations module would simplify the module count
  but create a circular dependency (Organizations needs remote state; remote state needs the bucket;
  the bucket would be created by Organizations).

## Decision

### Dedicated `state_bootstrap` Module with Local Backend

We create a dedicated Terraform module (`infra/modules/aws/state_bootstrap/`) whose sole
responsibility is creating the S3 state bucket and DynamoDB lock table. This module:

1. **Uses a local file backend** by overriding the root `remote_state` block in its
   `terragrunt.hcl`:

   ```hcl
   remote_state {
     backend = "local"
     generate = {
       path      = "backend.tf"
       if_exists = "overwrite_terragrunt"
     }
     config = {
       path = "${get_terragrunt_dir()}/terraform.tfstate"
     }
   }
   ```

   This breaks the circular dependency on the **first** apply. Once the bucket exists, the bootstrap's
   backend is migrated into that S3 bucket (see "State Lifecycle" below), so it no longer relies on the
   local file.

2. **Creates two resources** -- an S3 bucket and a DynamoDB table -- with hardened configurations:

   **S3 Bucket (`tfstate-mgmt-<MGMT_ACCOUNT_ID>`):**
   - Versioning: Enabled (allows state recovery from accidental corruption or deletion)
   - Encryption: AWS KMS with bucket key enabled (cost-effective server-side encryption)
   - Public access block: All four settings enabled (block_public_acls, block_public_policy,
     ignore_public_acls, restrict_public_buckets)

   **DynamoDB Table (`terraform-locks`):**
   - Hash key: `LockID` (String) -- standard Terraform lock key
   - Billing mode: PAY_PER_REQUEST (no capacity provisioning needed for infrequent IaC operations)

3. **Is completely separate from the Organizations module.** The state_bootstrap module has no
   knowledge of Organizations, OUs, accounts, or SCPs. The Organizations module has no knowledge
   of state storage. They share only the convention that the bucket name is
   `tfstate-mgmt-<MGMT_ACCOUNT_ID>` and the DynamoDB table is `terraform-locks`.

### State Lifecycle: Local for the First Apply, Then Migrated to S3

The local backend exists only to solve the bootstrap chicken-and-egg. Once the S3 bucket + DynamoDB
table exist, the bootstrap module's **own** state is migrated into that S3 backend
(`terragrunt init -migrate-state`) — so from then on it stores state in S3 with DynamoDB locking,
**exactly like every other module**. There is no permanent special case and no committed state file.

```text
First apply : backend = local  ->  creates bucket + lock table  ->  migrate state to S3
Thereafter  : backend = S3 (the bucket it created), with DynamoDB locking
```

The transient local `terraform.tfstate` is **not committed** (the repo's blanket `*.tfstate` gitignore
excludes it), and we deliberately do **not** commit it: a committed state file trips secret scanners and
needs a fragile gitignore exception, and once migrated to S3 there is nothing local worth keeping. (An
earlier iteration of this ADR proposed committing the bootstrap state to Git — superseded by this
migrate-to-S3 approach.)

**Disaster recovery** (the bucket itself is destroyed): the two resources have **deterministic names**,
so they are re-imported and re-migrated — no stored copy required:

```bash
terragrunt import 'aws_s3_bucket.state[0]'      tfstate-mgmt-<acct>
terragrunt import 'aws_dynamodb_table.locks[0]' terraform-locks
```

> **Status:** the migrate-to-S3 step is tracked as a follow-up; until it lands, the bootstrap state is
> still local + gitignored. The unit `README.md` documents the procedure.

### Deploy Order

The bootstrap creates a strict ordering requirement for initial AWS setup:

```text
Phase 1: state_bootstrap
  - Uses local backend (first apply only)
  - Creates S3 bucket + DynamoDB table
  - Migrates its own state into the new S3 bucket

Phase 2: organizations (and all other modules)
  - Uses S3 backend (bucket created in Phase 1)
  - Creates org, OUs, accounts, SCPs
  - State stored in S3
```

This ordering is enforced by convention and documentation, not by Terragrunt dependencies. The
`state_bootstrap` module does not declare a `dependency` block pointing to other modules, and no
other module declares a dependency on `state_bootstrap`. The dependency is implicit: if the S3
bucket does not exist, `terragrunt init` for any other AWS module will fail.

After the initial bootstrap, the ordering constraint relaxes. The state_bootstrap module can be
re-applied independently (e.g., to add tags or modify encryption settings) without affecting other
modules. Other modules can be applied without touching the bootstrap.

### Why Separate from the Organizations Module

The state_bootstrap and Organizations modules are deliberately separated despite both being
"foundational" infrastructure:

| Concern | state_bootstrap | organizations |
|---------|----------------|---------------|
| Backend | Local (first apply) → S3 | S3 (the bucket created by state_bootstrap) |
| Lifecycle | Run once, rarely modified | Run frequently (account/OU/SCP changes) |
| Blast radius | State storage only | Entire org structure, account governance |
| Dependencies | None | Depends on state_bootstrap (implicitly) |
| Destroy safety | Destroying would orphan all other state | Destroying would orphan all accounts |
| Change frequency | Almost never | Moderate (new accounts, SCP updates) |

Combining them would mean:

- The Organizations module would need a local backend, preventing it from using S3 state with
  locking.
- Any change to the org structure would also be a change to the state storage module, increasing
  blast radius.
- The local `terraform.tfstate` would grow to include the entire org structure (account details,
  SCPs), making a lost-state re-import far harder than re-importing two named resources.

### Idempotency and Re-Runs

The module uses the `count = var.create ? 1 : 0` pattern on all resources:

```hcl
resource "aws_s3_bucket" "state" {
  count  = var.create ? 1 : 0
  bucket = var.bucket_name
  tags   = var.tags
}
```

This means:

- Setting `create = false` cleanly skips all resource creation without errors.
- Re-running with `create = true` after the initial deployment shows no changes (idempotent).
- The `var.create` flag provides a kill switch if the module ever needs to be disabled without
  destroying resources.

## Consequences

### Positive

- **Full IaC coverage.** The state backend resources are tracked in Terraform state, satisfying
  audit requirements. Every attribute of the S3 bucket and DynamoDB table is code-reviewed and
  version-controlled.
- **Hardened defaults.** Unlike Terragrunt auto-create, the bootstrap module enforces KMS
  encryption with bucket keys, versioning, and a complete public access block. These settings are
  visible in code review.
- **Minimal blast radius.** The bootstrap module manages exactly 2 resources (bucket + table); its
  state is small and rarely changes.
- **Recoverable.** Even if the state is lost entirely, the resources can be re-imported by name
  (`terragrunt import 'aws_s3_bucket.state[0]' tfstate-mgmt-<acct>`) and re-migrated. The bucket and
  table names are deterministic.
- **No cross-tool dependency.** Unlike a CloudFormation bootstrap, this approach uses the same
  toolchain (OpenTofu + Terragrunt) as everything else in the repository.

### Negative

- **First-apply special case.** Only the bootstrap's *first* apply uses a local backend (before its
  state migrates to S3). That one step must be documented so new engineers don't miss the migration.
  After it, the bootstrap is an ordinary S3-backed module.
- **Manual deploy ordering.** The requirement to run `state_bootstrap` before any other AWS module
  is enforced by documentation, not by tooling. An engineer who skips this step will see a confusing
  `NoSuchBucket` error.
- **No locking during the first apply.** The initial (local-backend) apply has no DynamoDB lock, so
  concurrent first-applies could corrupt state. Negligible because it runs once; after migration to S3
  the bootstrap is locked like every other module.

### Risks

- **Loss of state before migration.** Before the migrate-to-S3 step, the only copy of the bootstrap
  state is the local file; deleting it loses the resource mapping (recover by re-import). After
  migration this risk is gone — the state is in S3 with versioning.
- **Bucket deletion.** If the S3 bucket is deleted, all AWS modules lose their state backend — and,
  post-migration, the bootstrap loses its own state too. Mitigation: versioning is enabled; MFA delete
  is a follow-up; recovery is re-import of the two named resources + re-migrate.
- **DynamoDB table deletion.** If the lock table is deleted, state locking is disabled and
  concurrent modifications become possible. Mitigation: same as bucket deletion -- protect via
  IAM policies and consider adding `prevent_destroy` lifecycle rules.

### What This Enables

- **Reproducible AWS bootstraps.** A new AWS environment (e.g., a separate management account for
  a different region or business unit) can be bootstrapped by copying the
  `infra/live/aws/mgmt/global/state-bootstrap/` directory, updating the bucket name and account ID,
  and running `terragrunt apply`.
- **Auditable state storage.** Compliance teams can inspect the bootstrap module code and verify
  that state storage meets encryption, access control, and versioning requirements.
- **Independent lifecycle management.** The state bucket can be modified (e.g., adding lifecycle
  rules, cross-region replication) without touching any other module.
