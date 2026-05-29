# Runbook: Add a New AWS Account

> **Module path:** `infra/modules/aws/organizations`
> **Live configuration:** `infra/live/aws/mgmt/global/organizations/terragrunt.hcl`
>
> **Last reviewed:** 2026-05-28

---

## Table of Contents

1. [Prerequisites](#prerequisites)
2. [Step 1: Choose the Organizational Unit](#step-1-choose-the-organizational-unit)
3. [Step 2: Add the Account to Terragrunt Inputs](#step-2-add-the-account-to-terragrunt-inputs)
4. [Step 3: Plan and Review](#step-3-plan-and-review)
5. [Step 4: Apply](#step-4-apply)
6. [Post-Creation Checklist](#post-creation-checklist)
7. [Rollback Procedure](#rollback-procedure)
8. [FAQ](#faq)

---

## Prerequisites

Before starting, confirm the following:

- [ ] You have IAM credentials (or an SSO session) for the **management account** with
  permissions to assume the Terraform execution role.
- [ ] You have a **unique email address** for the new account. AWS requires a globally
  unique email per account. Use the plus-alias pattern if needed (e.g.,
  `josh+newaccount@deeden.org`).
- [ ] You have decided which **Organizational Unit (OU)** the account belongs to.
- [ ] You have confirmed the account name with the relevant team lead or project owner.
- [ ] You have Terragrunt installed and the repository cloned locally.
- [ ] You are working on a feature branch (not `main`).

---

## Step 1: Choose the Organizational Unit

Review the current OU structure defined in `terragrunt.hcl`:

```text
Root
  |-- Platform                     (infra/shared services)
  |-- Workloads                    (application accounts)
       |-- Workloads/Preprod       (dev, staging, QA)
       |-- Workloads/Prod          (production)
       |-- Workloads/Regulated     (HIPAA / PCI scope)
```

**Selection guidance:**

| Account Purpose | Recommended OU | Rationale |
|---|---|---|
| Shared infrastructure (CI/CD, networking, logging) | `Platform` | Gets `protect-data-and-network` SCP |
| Development / staging | `Workloads/Preprod` | Inherits Workloads SCPs (data protection, tagging, IAM restriction) |
| Production workloads | `Workloads/Prod` | Same as Preprod, plus tighter change controls |
| HIPAA / PCI regulated workloads | `Workloads/Regulated` | Same as Workloads, intended for compliance-scoped apps |

SCPs that apply depend on the OU. Root-level SCPs (`baseline-guardrails`,
`protect-security-services`, `enforce-encryption`, `deny-regions`) apply to all accounts
regardless of OU placement. OU-specific SCPs are documented in
`docs/compliance/scp-control-mapping.md`.

Three roles are exempt from SCP deny statements: `OrganizationAccountAccessRole`
(break-glass), `PlatformDeployer` (Terragrunt apply), and `github-actions-terratest`
(CI test runner). See `docs/runbooks/modify-scps.md` for details on exempt roles.

---

## Step 2: Add the Account to Terragrunt Inputs

Edit `infra/live/aws/mgmt/global/organizations/terragrunt.hcl` and add the new account
to the `accounts` map:

```hcl
inputs = {
  # ... existing configuration ...

  accounts = {
    # Existing accounts
    "platform" = { email = "josh+platform@deeden.org", ou = "Platform" }
    "preprod"  = { email = "josh+preprod@deeden.org",  ou = "Workloads/Preprod" }

    # NEW: Add your account here
    "myapp-prod" = { email = "josh+myapp-prod@deeden.org", ou = "Workloads/Prod" }
  }
}
```

**Naming conventions:**

- Use lowercase, hyphen-separated names.
- Include the environment suffix if not obvious from the OU (`-dev`, `-staging`, `-prod`).
- Keep names under 50 characters (AWS limit).

**Important:** The `ou` value must exactly match a key in the `organizational_units` map.
If your desired OU does not exist yet, add it to `organizational_units` first (see
"Adding a New OU" in the FAQ below).

---

## Step 3: Plan and Review

Run Terragrunt plan from the organizations directory:

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt plan
```

**Expected output:**

You should see exactly one new resource:

```text
  # aws_organizations_account.this["myapp-prod"] will be created
  + resource "aws_organizations_account" "this" {
      + arn               = (known after apply)
      + email             = "josh+myapp-prod@deeden.org"
      + id                = (known after apply)
      + name              = "myapp-prod"
      + parent_id         = "ou-xxxx-xxxxxxxx"
      + close_on_deletion = false
      + tags              = { ... }
    }

Plan: 1 to add, 0 to change, 0 to destroy.
```

**Red flags -- stop and investigate if you see:**

- More than 1 resource being added (unless you also added an OU).
- Any resources being changed or destroyed.
- An error about a missing OU key -- verify the `ou` value matches `organizational_units`.
- The `parent_id` resolving to the root instead of your intended OU.

---

## Step 4: Apply

Once the plan looks correct:

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt apply
```

Confirm the apply prompt. AWS account creation typically takes 30-60 seconds.

**Expected output:**

```text
aws_organizations_account.this["myapp-prod"]: Creating...
aws_organizations_account.this["myapp-prod"]: Creation complete after 45s [id=123456789012]

Apply complete! Resources: 1 added, 0 changed, 0 destroyed.

Outputs:

account_ids = {
  "myapp-prod" = "123456789012"
  "platform"   = "111111111111"
  "preprod"    = "222222222222"
}
```

Record the new account ID from the output. You will need it for subsequent setup steps.

---

## Post-Creation Checklist

After the account is created, complete these steps:

### 1. Verify SCP Inheritance

```bash
# Get the new account ID
ACCOUNT_ID="123456789012"

# List SCPs effective on the account
aws organizations list-policies-for-target \
  --target-id "$ACCOUNT_ID" \
  --filter SERVICE_CONTROL_POLICY \
  --query 'Policies[].Name'
```

Expected: All root-level SCPs plus any OU-specific SCPs.

### 2. Verify Assume-Role Access

```bash
# Test assuming the OrganizationAccountAccessRole
aws sts assume-role \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/OrganizationAccountAccessRole" \
  --role-session-name test-access \
  --query 'Credentials.Expiration'
```

### 3. Configure SSO Access

If using AWS SSO (IAM Identity Center), assign the appropriate permission sets:

```bash
# List available permission sets
aws sso-admin list-permission-sets \
  --instance-arn <sso-instance-arn>

# Assign to the new account
aws sso-admin create-account-assignment \
  --instance-arn <sso-instance-arn> \
  --target-id "$ACCOUNT_ID" \
  --target-type AWS_ACCOUNT \
  --permission-set-arn <permission-set-arn> \
  --principal-type GROUP \
  --principal-id <group-id>
```

### 4. Apply Baseline Configuration

Deploy the account baseline (CloudTrail, Config, GuardDuty enrollment, etc.) using the
relevant Terragrunt modules for the new account. This typically involves:

- Creating the account-level directory structure under `infra/live/aws/<account>/`.
- Copying `env.hcl` and setting the `account_id` and `environment` values.
- Running the baseline modules (e.g., `cloudtrail`, `config`, `guardduty-member`).

### 5. Enable EBS Default Encryption

```bash
aws ec2 enable-ebs-encryption-by-default --region us-east-1
aws ec2 enable-ebs-encryption-by-default --region us-west-2
```

### 6. Block S3 Public Access (Account Level)

```bash
aws s3control put-public-access-block \
  --account-id "$ACCOUNT_ID" \
  --public-access-block-configuration \
    "BlockPublicAcls=true,IgnorePublicAcls=true,BlockPublicPolicy=true,RestrictPublicBuckets=true"
```

### 7. Verify Required Tags Are Enforced (Workloads OU Only)

If the account is in the Workloads OU tree, test that the tagging SCP is active:

```bash
# This should be DENIED (missing required tags)
aws ec2 run-instances \
  --image-id ami-xxxxxxxx \
  --instance-type t3.micro \
  --subnet-id subnet-xxxxxxxx
# Expected: AccessDeniedException

# This should succeed (tags present)
aws ec2 run-instances \
  --image-id ami-xxxxxxxx \
  --instance-type t3.micro \
  --subnet-id subnet-xxxxxxxx \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Environment,Value=prod},{Key=ManagedBy,Value=terraform},{Key=Owner,Value=myteam}]'
```

### 8. Update Documentation

- [ ] Add the new account to any internal account registry or CMDB.
- [ ] Update the architecture diagram if the OU structure changed.
- [ ] Notify the Security team of the new account for monitoring onboarding.

---

## Rollback Procedure

### If the Apply Failed Mid-Way

1. Check the Terraform state for a partially created account:

   ```bash
   cd infra/live/aws/mgmt/global/organizations
   terragrunt state list | grep "myapp-prod"
   ```

2. If the account exists in state but is in a bad state in AWS, you may need to import
   or remove it:

   ```bash
   # Remove from state (does NOT delete the AWS account)
   terragrunt state rm 'aws_organizations_account.this["myapp-prod"]'
   ```

3. Remove the account entry from `terragrunt.hcl` and re-apply.

### If the Account Was Created but Should Not Have Been

AWS accounts cannot be immediately deleted. The process is:

1. Remove the account from `terragrunt.hcl` inputs.
2. Remove the account from Terraform state:

   ```bash
   terragrunt state rm 'aws_organizations_account.this["myapp-prod"]'
   ```

   Note: `close_on_deletion` is set to `false` in the module, so `terraform destroy`
   will NOT close the account. This is a safety measure.

3. To close the account, use the AWS Console:
   - Sign in as root to the member account (use password reset via the account email).
   - Navigate to Account Settings and close the account.
   - The account enters a 90-day suspended state before permanent closure.

4. Alternatively, move the account to a "Suspended" OU with a deny-all SCP while waiting
   for closure.

### If the Account Was Placed in the Wrong OU

1. Update the `ou` value in `terragrunt.hcl`.
2. Run `terragrunt plan` -- you should see an in-place update to `parent_id`.
3. Run `terragrunt apply` -- the account moves to the correct OU.
4. Verify SCP inheritance has changed as expected.

---

## FAQ

### How do I add a new Organizational Unit?

Add it to the `organizational_units` map in `terragrunt.hcl`:

```hcl
organizational_units = {
  "Platform"            = { parent = null }
  "Workloads"           = { parent = null }
  "Workloads/Preprod"   = { parent = "Workloads" }
  "Workloads/Prod"      = { parent = "Workloads" }
  "Workloads/Regulated" = { parent = "Workloads" }
  "Sandbox"             = { parent = null }          # NEW: top-level OU
}
```

Set `parent = null` for root-level OUs or `parent = "ParentName"` for nested OUs.
Then run plan/apply. You may also need to update `scp_attachments` if the new OU
requires specific SCPs.

### What email format should I use?

Use the plus-alias pattern: `baseuser+accountname@domain.org`. This routes to the same
mailbox while satisfying AWS's unique-email requirement.

### Can I rename an account after creation?

Yes. Changing the `name` key in the `accounts` map will cause Terraform to destroy and
recreate the account, which is NOT what you want. Instead, use the AWS Console or CLI
to rename:

```bash
aws organizations update-account --account-id 123456789012 --name "new-name"
```

Then update the map key in `terragrunt.hcl` and import the account into the new key.

### What if I need to move an existing account into the organization?

Use `terraform import`:

```bash
terragrunt import 'aws_organizations_account.this["existing-account"]' 123456789012
```

Then add the corresponding entry to the `accounts` map.
