# ADR-004: AWS Account Management Strategy

**Date:** 2025-05-15

**Status:** Accepted

## Context

AWS Organizations account management must handle two fundamentally different scenarios:

1. **Greenfield deployments** -- Starting from scratch with no existing AWS Organization. The module
   must create the Organization, define the OU hierarchy, create member accounts, and attach SCPs.

2. **Brownfield adoptions** -- An AWS Organization already exists (possibly created manually or by
   another tool). The module must import the existing organization, its accounts, and its OU
   structure into Terraform state without modifying or disrupting running workloads.

The organization has an existing AWS Organization (`o-a4kjvito7o`) with existing accounts that were
created before this Terraform module existed. The module must be able to adopt these existing
resources while also creating new accounts and OUs going forward.

### Constraints

- **AWS account email uniqueness.** Every AWS account must have a globally unique email address.
  This is enforced by AWS and cannot be changed after account creation. Email addresses are a
  permanent, immutable identifier.
- **Account closure is irreversible.** Closing an AWS account triggers a 90-day suspension period
  after which the account is permanently deleted. Accidentally closing a production account could
  be catastrophic.
- **Role name drift.** The `OrganizationAccountAccessRole` IAM role is created automatically in
  new member accounts, but existing accounts may have been created with a different role name or
  may have had the role modified/deleted. Terraform's desire to manage this attribute conflicts
  with the reality of brownfield environments.
- **Import mechanics.** `terragrunt import` (wrapping `tofu import`) requires the resource address
  and the AWS resource ID. For Organizations resources, this means the organization ID, OU IDs, and
  account IDs must be known before import.

### Forces

- Terraform's declarative model assumes it creates and owns resources from birth. Importing
  existing resources requires careful state manipulation.
- The `aws_organizations_account` resource has a `close_on_deletion` attribute that defaults to
  `false` but could be accidentally set to `true`, creating a risk of account closure on
  `terraform destroy` or resource removal.
- Lifecycle meta-arguments (`prevent_destroy`, `ignore_changes`) are the primary mechanism for
  protecting critical resources from accidental modification.
- The module must be usable both for initial organization creation and for day-2 operations (adding
  accounts, moving accounts between OUs, modifying SCPs) without special modes or flags.

## Decision

### Dual-Mode Organization Management

The `create_organization` variable controls whether the module creates a new Organization or
adopts an existing one:

```hcl
variable "create_organization" {
  description = "Whether to create the AWS Organization (false to data-source an existing one)."
  type        = bool
  default     = false
}
```

**When `create_organization = true`** (greenfield):
- An `aws_organizations_organization` resource is created with the specified service access
  principals, enabled policy types, and `feature_set = "ALL"`.
- The resource has `lifecycle { prevent_destroy = true }` to prevent accidental deletion of the
  entire organization.

**When `create_organization = false`** (brownfield, the default):
- A `data.aws_organizations_organization.current` data source reads the existing organization.
- The root ID is extracted from the data source for OU and SCP attachment operations.

The root ID resolution is a single expression that handles both cases:

```hcl
root_id = local.create ? (
  var.create_organization
  ? aws_organizations_organization.this[0].roots[0].id
  : data.aws_organizations_organization.current[0].roots[0].id
) : null
```

### Protective Account Lifecycle Settings

#### `close_on_deletion = false`

Every `aws_organizations_account` resource is created with `close_on_deletion = false`:

```hcl
resource "aws_organizations_account" "this" {
  for_each          = local.create ? var.accounts : {}
  name              = each.key
  email             = each.value.email
  parent_id         = each.value.ou != null ? aws_organizations_organizational_unit.this[each.value.ou].id : local.root_id
  close_on_deletion = false
  # ...
}
```

This means:

- If the account is removed from the `accounts` map, Terraform will remove it from state but
  **will not close the AWS account**. The account continues to exist and must be dealt with
  manually.
- If `terraform destroy` is run, accounts are removed from the organization but not closed.
- This is a deliberate safety choice. Account closure should always be a conscious, manual
  operation with appropriate approvals, not an automated side effect of state manipulation.

#### `lifecycle { ignore_changes = [role_name] }`

The `role_name` attribute is excluded from Terraform's change detection:

```hcl
lifecycle { ignore_changes = [role_name] }
```

This is essential for brownfield adoption because:

- Existing accounts may have been created with a non-default role name.
- Some accounts may have had the OrganizationAccountAccessRole deleted or modified.
- Terraform would otherwise attempt to "fix" the role name on every plan, which is not possible
  for existing accounts (role_name is only settable at creation time).
- Without `ignore_changes`, every plan would show a perpetual diff for imported accounts.

#### `lifecycle { prevent_destroy = true }` on OUs

Organizational units also have `prevent_destroy = true`:

```hcl
resource "aws_organizations_organizational_unit" "this" {
  for_each  = local.create ? var.organizational_units : {}
  name      = each.key
  parent_id = local.ou_parent_map[each.key]
  lifecycle { prevent_destroy = true }
}
```

This prevents accidental OU deletion, which would orphan all accounts within the OU and detach
all SCP attachments.

### Email Uniqueness as a Permanent Constraint

AWS account email addresses are globally unique and permanently associated with an account. The
module surfaces this constraint through the account variable structure:

```hcl
accounts = {
  "platform" = { email = "josh+platform@deeden.org", ou = "Platform" }
  "preprod"  = { email = "josh+preprod@deeden.org",  ou = "Workloads/Preprod" }
}
```

The use of `+` subaddressing (e.g., `josh+platform@deeden.org`) is a common pattern that allows a
single email mailbox to serve as the root email for multiple AWS accounts. This works because:

- AWS treats each `+` variant as a unique email address.
- All emails are delivered to the same mailbox for centralized root account recovery.
- The pattern is documented and predictable.

Teams must maintain a registry of used email addresses to prevent conflicts. Attempting to create an
account with an already-used email will fail with an AWS API error.

### Brownfield Import Workflow

For an existing organization (e.g., `o-a4kjvito7o`), the import workflow is:

1. **Set `create_organization = false`** (the default). The module will use a data source to read
   the existing organization.

2. **Define the OU hierarchy** in the `organizational_units` variable to match the existing
   structure.

3. **Define accounts** in the `accounts` variable with correct email addresses and OU assignments.

4. **Run `terragrunt import`** for each existing resource:

   ```bash
   # Import existing OUs
   terragrunt import 'aws_organizations_organizational_unit.this["Platform"]' ou-xxxx

   # Import existing accounts
   terragrunt import 'aws_organizations_account.this["platform"]' 123456789012
   ```

5. **Run `terragrunt plan`** to verify no destructive changes. The `ignore_changes = [role_name]`
   prevents spurious diffs on imported accounts.

6. **Apply** any additive changes (new OUs, new accounts, SCP attachments).

### Greenfield Creation

For a brand-new organization:

1. **Set `create_organization = true`** in the module inputs.
2. **Define the desired OU hierarchy and accounts.**
3. **Run `terragrunt apply`.** The module creates the organization, OUs, accounts, and SCPs in a
   single apply (respecting dependency ordering via `parent_id` references).

The current deployment uses `create_organization = true`, indicating the organization is being
created fresh despite the existence of `o-a4kjvito7o`. This suggests an initial greenfield
deployment with plans to import existing resources as a follow-up, or a separate organization for
IaC-managed workloads.

## Consequences

### Positive

- **Single module for both modes.** The same module code handles greenfield creation and brownfield
  adoption. There is no separate "import mode" or "bootstrap mode" -- the difference is a single
  boolean variable.
- **Destruction safety.** `close_on_deletion = false` and `prevent_destroy = true` create multiple
  layers of protection against accidental resource loss. An operator must deliberately override
  these safeguards to cause damage.
- **Brownfield compatibility.** `ignore_changes = [role_name]` eliminates the most common source
  of perpetual diffs when importing existing accounts, making the import workflow smooth.
- **Predictable email pattern.** The `+` subaddressing convention is documented in the module
  inputs, making it easy to predict the email address for a new account.
- **Clear import path.** The `for_each` keying on account/OU name means import addresses are
  human-readable (e.g., `aws_organizations_account.this["platform"]`) rather than opaque indices.

### Negative

- **Manual import effort.** Each existing OU and account must be imported individually via
  `terragrunt import`. For organizations with dozens of accounts, this is tedious. Mitigation:
  the import commands can be scripted from the AWS Organizations API output.
- **No account email change.** If an account email needs to change (e.g., personnel change for root
  account recovery), this cannot be done through Terraform. It requires manual AWS Console access.
- **Orphaned accounts on removal.** Because `close_on_deletion = false`, removing an account from
  the `accounts` map leaves it running and potentially incurring costs. The team must have a
  process for identifying and handling orphaned accounts.
- **Import state consistency.** Importing existing resources assumes the real-world state matches
  the declared configuration. Any discrepancy (e.g., an account in a different OU than declared)
  will result in a plan that moves the account, which may be unexpected.

### Risks

- **Stale `environment_account_map`.** The safety validation in `_base.hcl` checks account IDs
  against a hardcoded map. If new environments are added without updating this map, the validation
  fails. Mitigation: CI should verify the map is complete.
- **Root account email compromise.** All AWS accounts use email addresses in the same domain. If
  the email domain is compromised, all AWS accounts are at risk of root-level takeover. Mitigation:
  enable MFA on all root accounts; use a dedicated email domain for AWS accounts.
- **Import race conditions.** If two operators attempt to import the same account simultaneously
  (before state locking is established), state corruption could occur. Mitigation: the DynamoDB lock
  table prevents concurrent state modifications once the bootstrap module has run.
