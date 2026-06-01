# Troubleshooting: AWS Organizations Module

> **Module path:** `infra/modules/aws/organizations`
> **Live configuration:** `infra/live/aws/mgmt/global/organizations/terragrunt.hcl`
>
> **Last reviewed:** 2026-06-01

---

## Table of Contents

1. [My Deploy/Action Is Denied](#my-deployaction-is-denied)
2. [SCP Is Too Large](#scp-is-too-large)
3. [Too Many SCPs on Target](#too-many-scps-on-target)
4. [Terraform Import Failed](#terraform-import-failed)
5. [OU Dependency Cycle](#ou-dependency-cycle)
6. [Region-Denied Service Is Not Global](#region-denied-service-is-not-global)
7. [Common Terragrunt Errors](#common-terragrunt-errors)
8. [Account Creation Failures](#account-creation-failures)
9. [State Drift and Reconciliation](#state-drift-and-reconciliation)

---

## My Deploy/Action Is Denied

### Symptom

An API call returns `AccessDenied` or `Client.UnauthorizedOperation`, even though the
IAM role has the necessary permissions. The same action may work in a different account.

### Diagnosis

**Step 1: Confirm it is an SCP denial, not an IAM denial.**

SCP denials and IAM denials produce the same error code. To distinguish them:

```bash
# If the error includes an encoded message, decode it:
aws sts decode-authorization-message \
  --encoded-message "<encoded-message>" \
  --query 'DecodedMessage' --output text | jq .
```

The decoded message contains a `context` field. Look for `"explicitDeny": true` with
a policy source that references the organization. If the decode does not provide
clarity, check CloudTrail.

**Step 2: Find the specific event in CloudTrail.**

```bash
aws cloudtrail lookup-events \
  --lookup-attributes AttributeKey=EventName,AttributeValue=<action-name> \
  --start-time "$(date -d '-1 hour' +%Y-%m-%dT%H:%M:%SZ)" \
  --max-items 10 \
  | jq '.Events[] | {eventTime, eventName, errorCode, errorMessage, username: .Username}'
```

**Step 3: Identify which SCP contains the deny.**

List all SCPs effective on the account:

```bash
ACCOUNT_ID="<account-id>"

# Direct SCPs on the account
aws organizations list-policies-for-target \
  --target-id "$ACCOUNT_ID" \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].{Name:Name,Id:Id}' --output table

# SCPs on the parent OU
PARENT=$(aws organizations list-parents --child-id "$ACCOUNT_ID" \
  --query 'Parents[0].Id' --output text)
aws organizations list-policies-for-target \
  --target-id "$PARENT" \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].{Name:Name,Id:Id}' --output table

# SCPs on the root
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations list-policies-for-target \
  --target-id "$ROOT_ID" \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].{Name:Name,Id:Id}' --output table
```

For each SCP, inspect its content and search for the denied action:

```bash
aws organizations describe-policy --policy-id "<policy-id>" \
  --query 'Policy.Content' --output text | jq '.Statement[] | select(
    (.Action // [] | any(. == "<action>")) or
    (.NotAction // [] | length > 0)
  )'
```

**Step 4: Check conditions.**

Most SCPs in this module include an `ArnNotLike` condition for exempt roles. Verify:

- Is the calling role in the `exempt_roles` list?
- Does the role ARN match the pattern `arn:aws:iam::*:role/<role-name>`?
- If the SCP uses other conditions (e.g., `ec2:Encrypted`, `aws:RequestedRegion`),
  verify the request meets those conditions.

### Resolution

See `docs/runbooks/incident-scp-blocking.md` for the full incident response procedure.

Quick fixes:

| Root Cause | Fix |
|---|---|
| Role is not exempt and should be | Add to `var.exempt_roles` |
| Action is in a denied region | Switch to an allowed region or update `var.allowed_regions` |
| Resource is missing required tags | Add tags to the resource |
| Resource is unencrypted | Enable encryption on the resource |
| Using root user | Use a named IAM role instead |
| Using an IAM user | Use SSO or assume a role |

---

## SCP Is Too Large

### Symptom

Terraform apply fails with:

```text
Error: error creating Organizations Policy: MalformedPolicyDocumentException:
  SCP content is too large. The maximum size is 5120 bytes.
```

Or plan shows a policy with content exceeding 5,120 bytes.

### Diagnosis

Check the size of each rendered SCP:

```bash
# Method 1: From the AWS API (for existing policies)
for policy_id in $(aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].Id' --output text); do
  name=$(aws organizations describe-policy --policy-id "$policy_id" \
    --query 'Policy.PolicySummary.Name' --output text)
  size=$(aws organizations describe-policy --policy-id "$policy_id" \
    --query 'Policy.Content' --output text | wc -c)
  pct=$((size * 100 / 5120))
  echo "$name: $size bytes (${pct}% of limit)"
done

# Method 2: From Terraform plan (for pending changes)
cd infra/live/aws/mgmt/global/organizations
terragrunt plan -out=plan.bin
terragrunt show -json plan.bin | \
  jq -r '.resource_changes[] |
    select(.type == "aws_organizations_policy") |
    "\(.change.after.name): \(.change.after.content | length) bytes"'
```

### Strategies for Shrinking

**1. Use action wildcards:**

```hcl
# Before (verbose):
actions = ["iam:AttachRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePolicy",
           "iam:DeleteRolePolicy", "iam:DeleteRole"]

# After (compact):
actions = ["iam:*RolePolicy", "iam:DeleteRole"]
```

Be careful with wildcards -- ensure they do not inadvertently match actions you want to
allow. Test with `aws iam simulate-custom-policy` or by reviewing the AWS IAM Actions
reference.

**2. Merge statements with identical conditions:**

If two statements have the same `effect`, `resources`, and `conditions` but different
`actions`, merge them:

```hcl
# Before: 2 statements
statement {
  sid     = "ProtectCloudTrail"
  effect  = "Deny"
  actions = ["cloudtrail:StopLogging", "cloudtrail:DeleteTrail"]
  # ...conditions...
}
statement {
  sid     = "ProtectConfig"
  effect  = "Deny"
  actions = ["config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder"]
  # ...conditions...
}

# After: 1 statement (saves ~150 bytes)
statement {
  sid     = "ProtectAuditServices"
  effect  = "Deny"
  actions = [
    "cloudtrail:StopLogging", "cloudtrail:DeleteTrail",
    "config:StopConfigurationRecorder", "config:DeleteConfigurationRecorder",
  ]
  # ...conditions...
}
```

**3. Split into multiple SCPs:**

Move groups of statements to a new SCP. Attach both SCPs to the same target. AWS
evaluates all attached SCPs -- a deny in any SCP is enforced.

```hcl
# Instead of one large "protect-security-services" SCP, split into:
# - "protect-audit-logging" (CloudTrail, Config, Flow Logs)
# - "protect-threat-detection" (GuardDuty, Security Hub, Access Analyzer)
```

Remember the 5-SCP-per-target limit when splitting.

**4. Shorten condition values:**

If exempt role names are long, use shorter names. Each character in `local.exempt_role_arns`
is repeated across every statement.

**5. Remove the SID:**

SIDs are optional and consume bytes. Remove them if you do not need them for
CloudTrail identification (not recommended -- SIDs help greatly with troubleshooting).

### The HIPAA SCP Special Case

The `hipaa-eligible-services` SCP is the largest because it enumerates ~117 services in
a `NotAction` block. If it approaches the limit:

- Check if AWS has consolidated any service namespaces.
- Remove services your organization does not use (but be aware this reduces the
  allowlist, not the policy size -- `NotAction` means "everything except these").
- Consider using a tag-based condition instead of a service allowlist if your
  architecture supports it.

---

## Too Many SCPs on Target

### Symptom

Terraform apply fails with:

```text
Error: error attaching Organizations Policy: ConstraintViolationException:
  You have attached the maximum number of policies to the specified target.
```

### Diagnosis

AWS limits each target (root, OU, or account) to **5 SCPs**, including the default
`FullAWSAccess` SCP that AWS attaches automatically.

Check the current count:

```bash
TARGET_ID="<root-or-ou-id>"
aws organizations list-policies-for-target \
  --target-id "$TARGET_ID" \
  --filter SERVICE_CONTROL_POLICY \
  --query 'length(Policies)'
```

Also check if the default `FullAWSAccess` is still attached (it counts toward the limit):

```bash
aws organizations list-policies-for-target \
  --target-id "$TARGET_ID" \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[?Name==`FullAWSAccess`]'
```

### Resolution

**Option 1: Remove the FullAWSAccess SCP (if custom SCPs provide sufficient allow).**

The default `FullAWSAccess` SCP is an explicit `Allow *`. If your custom SCPs only use
`Deny` statements (which is the case for all SCPs in this module), the `FullAWSAccess`
is still needed -- without it, nothing is allowed. Do NOT remove it unless you have an
explicit `Allow` SCP attached.

**Option 2: Consolidate SCPs.**

Merge related SCPs into fewer policies. For example, merge `protect-security-services`
and `enforce-encryption` into a single SCP if their combined size is under 5,120 bytes.

**Option 3: Rebalance across the OU hierarchy.**

SCPs applied at a parent OU are inherited by all child OUs. If the root already has 4
custom SCPs attached, move some to specific child OUs where they are actually needed:

```hcl
# Before: 5 SCPs on root (at the limit)
scp_attachments = {
  "root" = ["baseline-guardrails", "protect-security-services",
            "enforce-encryption", "deny-regions", "protect-data-and-network"]
}

# After: 4 on root, 1 on specific OUs
scp_attachments = {
  "root"      = ["baseline-guardrails", "protect-security-services",
                 "enforce-encryption", "deny-regions"]
  "Platform"  = ["protect-data-and-network"]
  "Workloads" = ["protect-data-and-network"]
}
```

**Option 4: Use nested OUs to stack SCPs.**

Create an intermediate OU to gain an additional 5-SCP slot:

```text
Root (4 SCPs)
  |-- Workloads (3 SCPs)
       |-- Workloads/Regulated (2 more SCPs, inherits parent SCPs)
```

Each level can have up to 5 SCPs, and all are evaluated cumulatively.

---

## Terraform Import Failed

### Symptom

Running `terragrunt import` for an existing organization, OU, account, or SCP fails.

### Common Errors and Fixes

#### Error: "Resource already managed by Terraform"

```text
Error: Resource already exists in state
```

The resource is already in the Terraform state file. Check with:

```bash
terragrunt state list | grep organizations
```

If the resource exists but with stale data, remove it first (this does NOT delete the
AWS resource):

```bash
terragrunt state rm 'aws_organizations_account.this["account-name"]'
```

Then re-import.

#### Error: "Cannot import non-existent resource"

The ID you provided does not match an existing AWS resource. Verify the ID:

```bash
# For accounts:
aws organizations describe-account --account-id <id>

# For OUs:
aws organizations describe-organizational-unit --organizational-unit-id <ou-id>

# For SCPs:
aws organizations describe-policy --policy-id <policy-id>
```

#### Error: "Error importing: expected format 'target_id:policy_id'"

SCP attachments require a composite import ID:

```bash
terragrunt import \
  'aws_organizations_policy_attachment.this["root/baseline-guardrails"]' \
  "<root-id>:<policy-id>"
```

#### Error: "Organization features must be set to ALL"

```text
Error: error reading AWS Organization: organization features are not set to ALL
```

The organization was created with `CONSOLIDATED_BILLING` features instead of `ALL`.
You cannot import it with `feature_set = "ALL"`. Either:

1. Enable all features in the AWS Console first.
2. Or set `create_organization = false` to use a data source instead.

**General import commands reference:**

```bash
# Import the organization itself
terragrunt import 'aws_organizations_organization.this[0]' <org-id>

# Import an OU
terragrunt import 'aws_organizations_organizational_unit.this["Workloads"]' <ou-id>

# Import an account
terragrunt import 'aws_organizations_account.this["myapp"]' <account-id>

# Import an SCP
terragrunt import 'aws_organizations_policy.this["baseline-guardrails"]' <policy-id>

# Import an SCP attachment
terragrunt import \
  'aws_organizations_policy_attachment.this["root/baseline-guardrails"]' \
  "<target-id>:<policy-id>"
```

---

## OU Dependency Cycle

### Symptom

Terraform plan or apply fails with:

```text
Error: Cycle: aws_organizations_organizational_unit.this["Parent"],
  aws_organizations_organizational_unit.this["Child"]
```

Or:

```text
Error: Invalid index: The given key does not identify an element in this collection.
```

### Diagnosis

The `organizational_units` variable uses self-referencing keys for parent-child
relationships. Terraform must create parent OUs before children. The module resolves
parents via `local.ou_parent_map`:

```hcl
ou_parent_map = { for k, v in var.organizational_units :
  k => v.parent == null ? local.root_id : aws_organizations_organizational_unit.this[v.parent].id
}
```

A cycle occurs if:

1. **Circular reference:** OU "A" has `parent = "B"` and OU "B" has `parent = "A"`.
2. **Missing parent:** OU "Child" has `parent = "NonExistent"` and `NonExistent` is not
   in the `organizational_units` map.
3. **Self-reference:** OU "X" has `parent = "X"`.

### Resolution

**Verify the OU hierarchy is a valid tree:**

```text
# Correct: tree structure with root-level OUs having parent = null
"Platform"            = { parent = null }          # Root level
"Workloads"           = { parent = null }          # Root level
"Workloads/Preprod"   = { parent = "Workloads" }   # Child of Workloads
"Workloads/Prod"      = { parent = "Workloads" }   # Child of Workloads
"Workloads/Regulated" = { parent = "Workloads" }   # Child of Workloads
```

Rules:

- Every OU must have either `parent = null` (root-level) or `parent = "<existing-ou-key>"`.
- The parent key must exactly match another key in the `organizational_units` map.
- There must be no circular chains.
- Terraform processes `for_each` resources in a single pass, so deeply nested OUs
  (grandchild, great-grandchild) may require multiple applies on initial creation. After
  the first apply creates the parent, the second apply creates the child.

**For deep nesting (3+ levels):**

```hcl
# This requires 2 applies: first creates "Workloads", second creates "Workloads/Prod",
# third creates "Workloads/Prod/Critical"
"Workloads"                = { parent = null }
"Workloads/Prod"           = { parent = "Workloads" }
"Workloads/Prod/Critical"  = { parent = "Workloads/Prod" }
```

If you see errors about missing keys, run `terragrunt apply` again. Terraform's dependency
resolution usually handles two-level nesting in a single pass, but three or more levels
may need sequential applies.

---

## Region-Denied Service Is Not Global

### Symptom

A service that operates globally (no region-specific endpoints) is being denied by the
`deny-regions` SCP. Common examples:

- AWS SSO actions fail.
- Cost Explorer queries are blocked.
- Support cases cannot be created.
- Tag policies cannot be managed.

### Diagnosis

The `deny-regions` SCP uses `NotAction` to exempt global services. If a global service
is not in the `NotAction` list, its API calls will be denied when `aws:RequestedRegion`
is not in the allowed list.

Check the current exemption list in `scps.tf`:

```hcl
not_actions = [
  "iam:*", "sts:*", "organizations:*", "route53:*", "route53domains:*",
  "cloudfront:*", "waf:*", "wafv2:*", "waf-regional:*", "shield:*",
  "globalaccelerator:*", "support:*", "health:*", "ce:*", "cur:*",
  "budgets:*", "billing:*", "account:*", "access-analyzer:*",
  "trustedadvisor:*", "sso:*", "pricing:*", "tag:*", "artifact:*",
  "tax:*", "freetier:*", "invoicing:*", "payments:*", "savingsplans:*",
]
```

If the failing service is not in this list, it needs to be added.

### Resolution

1. **Verify the service is truly global.** Check the AWS documentation:
   - [AWS Services That Support Global Endpoints](https://docs.aws.amazon.com/general/latest/gr/rande.html)
   - If the service has regional endpoints, the service is NOT global and should
     be used in an allowed region instead.

2. **Add the service to the NotAction list:**

   Edit `scps.tf`, locate the `deny_regions` data source, and add the service:

   ```hcl
   not_actions = [
     # ... existing services (alphabetical order) ...
     "newglobalservice:*",
   ]
   ```

3. **Validate and apply:**

   ```bash
   cd infra/live/aws/mgmt/global/organizations
   terragrunt plan   # Should show deny-regions SCP content update
   terragrunt apply
   ```

### Known Global Services Not in AWS Default List

These services are sometimes missed. Verify whether your organization uses them and
add if needed:

| Service | Namespace | Status |
|---|---|---|
| Resource Explorer | `resource-explorer-2:*` | Regional but with global search |
| Compute Optimizer | `compute-optimizer:*` | Regional |
| Service Quotas | `servicequotas:*` | Regional with global data |
| License Manager | `license-manager:*` | Regional |
| RAM (Resource Access Manager) | `ram:*` | Regional |
| Cost Anomaly Detection | Part of `ce:*` | Covered |

---

## Common Terragrunt Errors

### Error: "find_in_parent_folders: no file found"

```text
Error: Error in function call: Call to function "find_in_parent_folders" failed:
  Could not find a aws/_base.hcl in any of the parent folders
```

**Cause:** Terragrunt cannot locate the referenced include file by walking up the
directory tree from the current module.

**Resolution:**

1. Verify you are running Terragrunt from the correct directory:

   ```bash
   pwd
   # Should be: infra/live/aws/mgmt/global/organizations
   ```

2. Verify the include file exists:

   ```bash
   ls -la infra/live/aws/_base.hcl
   ```

3. If the file exists but Terragrunt cannot find it, check the `find_in_parent_folders`
   argument. The function searches from the current `.hcl` file's directory upward. The
   argument is a relative path suffix to match.

### Error: "missing _versions.hcl"

```text
Error: Error in function call: read_terragrunt_config: no file found matching _versions.hcl
```

**Cause:** The `_base.hcl` reads `_versions.hcl` for module source pins, but the file
is not found.

**Resolution:**

```bash
# Verify it exists
ls infra/live/aws/_versions.hcl

# If missing, check if it was recently moved or renamed
git log --diff-filter=D -- '*_versions.hcl'
```

### Error: "locals block not found in common.hcl / env.hcl / region.hcl / workload.hcl"

```text
Error: Could not find a common.hcl in any of the parent folders
```

**Cause:** The organizations module lives at `infra/live/aws/mgmt/global/organizations`,
and `_base.hcl` expects configuration files at each level of the hierarchy. For the
management account, you need:

- `infra/live/aws/common.hcl` -- cloud-wide defaults
- `infra/live/aws/mgmt/env.hcl` -- management account environment config
- `infra/live/aws/mgmt/global/region.hcl` -- region config (even for global resources)
- A `network.hcl` and `workload.hcl` somewhere in the hierarchy

**Resolution:** Check that all required configuration files exist in the path hierarchy.
For "global" resources that do not fit neatly into the region/workload structure, you
may need stub files:

```hcl
# region.hcl stub for global resources
locals {
  region      = "global"
  region_abbv = "gbl"
  region_tags = {}
}
```

### Error: "Unsupported Terraform Core version"

```text
Error: This configuration does not support Terraform version X.Y.Z
```

**Resolution:** Check the version constraint in `_versions.hcl` and update your
local Terraform/OpenTofu version:

```bash
terraform version
# Compare with required_version in _versions.hcl
```

### Error: "Backend configuration changed"

```text
Error: Backend configuration changed
```

**Cause:** The remote state configuration (S3 bucket, DynamoDB table, key path) has
changed between runs.

**Resolution:**

```bash
# Re-initialize with migration
terragrunt init -migrate-state

# Or reconfigure without migrating
terragrunt init -reconfigure
```

---

## Account Creation Failures

### Error: "Email already associated with an account"

```text
Error: error creating Organizations Account: ConstraintViolationException:
  An account with the email address already exists in the organization.
```

**Resolution:** Each AWS account requires a globally unique email. Use the plus-alias
pattern with a different suffix.

### Error: "Account limit exceeded"

```text
Error: error creating Organizations Account: ConstraintViolationException:
  You have exceeded the limit on the number of accounts in your organization.
```

**Resolution:** Request a limit increase via AWS Support. The default is 10 accounts.
Go to Service Quotas > AWS Organizations > Maximum number of accounts.

### Error: "Account creation in progress"

```text
Error: error creating Organizations Account: FinalizingCreationException
```

**Resolution:** AWS is still finalizing the account. Wait 5-10 minutes and try
`terragrunt apply` again. The resource may already be in a `SUCCEEDED` state by then.

---

## State Drift and Reconciliation

### Symptom

`terragrunt plan` shows unexpected changes, such as:

- SCPs being recreated even though no code changed.
- Attachments being added/removed that were not in the code change.
- OUs or accounts showing as new resources when they already exist.

### Diagnosis

Check for out-of-band changes (changes made in the AWS Console or CLI without Terraform):

```bash
# Compare state to reality
cd infra/live/aws/mgmt/global/organizations
terragrunt state list

# For each suspicious resource, compare state to AWS
terragrunt state show 'aws_organizations_policy.this["baseline-guardrails"]'

# Then check AWS
aws organizations describe-policy --policy-id <id-from-state>
```

### Resolution

1. **If resources were modified out-of-band:** Run `terragrunt apply` to bring AWS back
   in line with the code. Or, if the out-of-band change is desired, update the code to
   match and then run `terragrunt plan` to confirm no diff.

2. **If resources were created out-of-band:** Import them into state:

   ```bash
   terragrunt import '<resource-address>' '<aws-id>'
   ```

3. **If state is corrupted:** As a last resort, remove the resource from state and
   re-import:

   ```bash
   terragrunt state rm '<resource-address>'
   terragrunt import '<resource-address>' '<aws-id>'
   ```

4. **Refresh state without applying:**

   ```bash
   terragrunt plan -refresh-only
   terragrunt apply -refresh-only
   ```

   This updates the state file to match the current AWS state without making any
   changes to AWS resources.
