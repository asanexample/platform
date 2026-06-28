# Runbook: Modify Service Control Policies

> **Module path:** `infra/modules/aws/organizations/scps.tf`
> **Live configuration:** `infra/live/aws/mgmt/global/organizations/terragrunt.hcl`
>
> **Last reviewed:** 2026-06-01

---

## Table of Contents

1. [Overview](#overview)
2. [Modifying a Default SCP](#modifying-a-default-scp)
3. [Adding a New SCP to the Default Set](#adding-a-new-scp-to-the-default-set)
4. [Using service_control_policies Override](#using-service_control_policies-override)
5. [Adjusting SCP Attachments](#adjusting-scp-attachments)
6. [Size Validation](#size-validation)
7. [Testing Changes Safely](#testing-changes-safely)
8. [Common Modifications](#common-modifications)
9. [Pre-Merge Checklist](#pre-merge-checklist)

---

## Overview

The organizations module provides two approaches for managing SCPs:

1. **Default SCPs (recommended):** Eight built-in SCPs defined as
   `aws_iam_policy_document` data sources in `scps.tf`. These are used automatically
   when `var.service_control_policies` is `null` (the default). **Only seven are created
   by default** — the eighth, `hipaa-eligible-services`, is conditional on
   `enable_hipaa_scp = true`.

2. **Custom override:** Set `var.service_control_policies` to a `map(string)` of
   pre-rendered JSON policy documents. This **replaces all default SCPs entirely** -- the
   built-in data sources are not evaluated when this variable is set.

Most changes should use approach 1 (editing `scps.tf`) to maintain the benefits of
Terraform's `aws_iam_policy_document` data source (HCL validation, variable
interpolation, automatic JSON formatting).

---

## Modifying a Default SCP

### When to Use This Approach

- Adding or removing a statement from an existing SCP.
- Changing the actions, conditions, or resources of a statement.
- Adding a new service to the global-services exemption list in `deny-regions`.

### Procedure

1. **Open `scps.tf`** and locate the relevant `data "aws_iam_policy_document"` block.
   Each SCP is clearly labeled with a comment (e.g., `# SCP 3: enforce-encryption`).

2. **Make your changes.** For example, the statement below denies unencrypted S3 uploads in the
   `enforce-encryption` SCP (shown as a syntax example — this particular `DenyUnencryptedS3Uploads`
   statement already ships in the module; use the same shape for a genuinely new statement):

   ```hcl
   # Statement inside data "aws_iam_policy_document" "enforce_encryption"
   statement {
     sid       = "DenyUnencryptedS3Uploads"
     effect    = "Deny"
     actions   = ["s3:PutObject"]
     resources = ["*"]
     condition {
       test     = "StringNotEquals"
       variable = "s3:x-amz-server-side-encryption"
       values   = ["aws:kms", "AES256"]
     }
     condition {
       test     = "Null"
       variable = "s3:x-amz-server-side-encryption"
       values   = ["true"]
     }
   }
   ```

3. **Update the compliance mapping** in `docs/compliance/scp-control-mapping.md` with
   the new statement's framework control references.

4. **Validate the size** (see [Size Validation](#size-validation)).

5. **Test the change** (see [Testing Changes Safely](#testing-changes-safely)).

6. **Run plan and apply:**

   ```bash
   cd infra/live/aws/mgmt/global/organizations
   terragrunt plan
   # Expect: aws_organizations_policy.this["enforce-encryption"] will be updated in-place
   terragrunt apply
   ```

### Modifying Exempt Roles

To change which roles are exempt from SCP deny statements, modify `var.exempt_roles`
in `terragrunt.hcl`. **The current live value has SEVEN entries — keep them ALL and append**;
dropping `PlatformDeployer`/`github-actions-terratest` breaks Terragrunt apply / Terratest CI,
dropping the `crossplane-*` entries breaks environment ECR/IAM provisioning, and dropping either
anchored `*-eks-karpenter-*` entry breaks Karpenter node provisioning for that cluster (ADR-078):

```hcl
inputs = {
  exempt_roles = [
    "OrganizationAccountAccessRole", # break-glass (AWS-created per account)
    "github-actions-terratest",      # CI integration tests — DO NOT REMOVE
    "PlatformDeployer",              # IaC apply role — DO NOT REMOVE
    "crossplane-ecr-provisioner",    # environment ECR provisioning — DO NOT REMOVE
    "crossplane-provisioner-*",      # environment IAM/EKS provisioning — DO NOT REMOVE
    "platform-use1-eks-karpenter-*", # Karpenter node provisioning, platform (ADR-078) — DO NOT REMOVE
    "preprod-use1-eks-karpenter-*",  # Karpenter node provisioning, preprod (ADR-078) — DO NOT REMOVE
    "EmergencyBreakGlassRole",       # <-- new role being added
  ]
}
```

> The Karpenter entries are **anchored per-cluster** (`<cluster>-eks-karpenter-*`), not a leading-wildcard
> `*-karpenter-*`, so an unrelated role merely containing `-karpenter-` can't inherit the exemption (security
> audit). Add a new cluster's anchored pattern when you stand one up.

The module builds the ARN pattern `arn:aws:iam::*:role/<role-name>` for each entry.
Adding roles here weakens SCP enforcement -- document the justification and obtain
security team approval.

---

## Adding a New SCP to the Default Set

### When to Use This Approach

- You need a new category of preventive control that does not fit into any existing SCP.
- You want the new SCP to be part of the module's built-in defaults.

### Procedure

1. **Add the data source in `scps.tf`:**

   ```hcl
   # SCP 9: deny-public-rds — Prevent public RDS instances
   data "aws_iam_policy_document" "deny_public_rds" {
     count = local.create && var.service_control_policies == null ? 1 : 0

     statement {
       sid       = "DenyPublicRdsInstances"
       effect    = "Deny"
       actions   = ["rds:CreateDBInstance", "rds:ModifyDBInstance"]
       resources = ["*"]
       condition {
         test     = "Bool"
         variable = "rds:PubliclyAccessible"
         values   = ["true"]
       }
       condition {
         test     = "ArnNotLike"
         variable = "aws:PrincipalArn"
         values   = local.exempt_role_arns
       }
     }
   }
   ```

2. **Register the SCP in the `default_scps` local in `main.tf`:**

   Add the new entry to the map inside the `default_scps` local:

   ```hcl
   locals {
     default_scps = merge(
       { for k, v in {
         # ... existing SCPs ...
         "deny-public-rds" = data.aws_iam_policy_document.deny_public_rds[0].json
         } : k => v if local.create && var.service_control_policies == null
       },
       # ... hipaa conditional block ...
     )
   }
   ```

3. **Add a default attachment in `variables.tf`:**

   Update the `scp_attachments` default to include the new SCP:

   ```hcl
   variable "scp_attachments" {
     default = {
       "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
       "Platform"  = ["protect-data-and-network"]
       "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users", "deny-public-rds"]
     }
   }
   ```

   Or override in `terragrunt.hcl` if you prefer not to change the module default.

4. **Validate, test, plan, and apply** as described below.

---

## Using service_control_policies Override

### When to Use This Approach

- You need complete control over SCP JSON and cannot use HCL data sources.
- You are migrating from a different SCP management tool and have pre-built JSON.
- You need to test a policy change without modifying the module source.

### How It Works

Setting `service_control_policies` to a non-null value **replaces all 8 default SCPs**.
The value is a `map(string)` where keys are SCP names and values are raw JSON policy
documents.

```hcl
# In terragrunt.hcl
inputs = {
  service_control_policies = {
    "custom-deny-all" = jsonencode({
      Version = "2012-10-17"
      Statement = [{
        Sid       = "DenyEverything"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = {
          ArnNotLike = {
            "aws:PrincipalArn" = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
          }
        }
      }]
    })
  }

  scp_attachments = {
    "root" = ["custom-deny-all"]
  }
}
```

**Warning:** When you switch from default SCPs to custom SCPs (or vice versa), Terraform
will destroy the old `aws_organizations_policy` resources and create new ones. This means
there is a brief window during apply where old attachments are removed before new ones are
created. Plan for this and consider applying during a maintenance window.

---

## Adjusting SCP Attachments

### Changing Which OUs Receive Which SCPs

The `scp_attachments` variable maps target names to lists of SCP names. The **module default** is:

```hcl
scp_attachments = {
  "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
  "Platform"  = ["protect-data-and-network"]
  "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
}
```

> **Note:** the **live** `terragrunt.hcl` overrides the Platform OU to also carry `require-tagging` +
> `restrict-iam-users` (matching Workloads — a security-audit OU-coverage fix), so the live Platform value is
> `["protect-data-and-network", "require-tagging", "restrict-iam-users"]`, not the module default shown above.

**Target names:**

- `"root"` refers to the organization root (applies to all accounts).
- Any other string must match a key in `organizational_units`.

**To attach an SCP to a specific OU:**

```hcl
scp_attachments = {
  # ... existing ...
  "Workloads/Regulated" = ["hipaa-eligible-services"]
}
```

**To remove an SCP from an OU,** remove it from the list. Terraform will destroy the
`aws_organizations_policy_attachment` resource.

### Attachment Limits

AWS allows a maximum of **5 SCPs per target** (OU or account). The module does not
validate this limit. Check before applying:

```bash
# Count attachments per target — live, straight from AWS Organizations (the real 5-per-target limit).
# Lists the root + every OU, then counts SERVICE_CONTROL_POLICY attachments on each.
root_id=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
ou_ids=$(aws organizations list-organizational-units-for-parent --parent-id "$root_id" \
  --query 'OrganizationalUnits[].Id' --output text)
for target in "$root_id" $ou_ids; do
  count=$(aws organizations list-policies-for-target --target-id "$target" \
    --filter SERVICE_CONTROL_POLICY --query 'length(Policies)' --output text)
  echo "$target: $count SCPs"
done
```

(To check **before** applying, count the lists in the `scp_attachments` map in `terragrunt.hcl` directly — each
target's value is the list of SCP names attached to it.)

If you are at the limit, consider consolidating SCPs or rebalancing across OUs.

---

## Size Validation

AWS enforces a **5,120-byte limit** on SCP JSON content. The HIPAA eligible services
SCP is particularly large due to the extensive `NotAction` list.

### Check Rendered Size Before Applying

1. **Use Terraform plan output:**

   ```bash
   cd infra/live/aws/mgmt/global/organizations
   terragrunt plan -out=plan.bin
   terragrunt show -json plan.bin | \
     jq -r '.resource_changes[] |
       select(.type == "aws_organizations_policy") |
       "\(.change.after.name): \(.change.after.content | length) bytes"'
   ```

2. **Check the rendered JSON directly (if you have the data source output):**

   ```bash
   # After apply, check existing policy sizes
   for policy in $(aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
     --query 'Policies[].Id' --output text); do
     name=$(aws organizations describe-policy --policy-id "$policy" \
       --query 'Policy.PolicySummary.Name' --output text)
     size=$(aws organizations describe-policy --policy-id "$policy" \
       --query 'Policy.Content' --output text | wc -c)
     echo "$name: $size bytes"
   done
   ```

3. **Estimate size for a new statement:**

   Each statement adds roughly 100-300 bytes depending on the number of actions and
   conditions. If you are approaching 4,500 bytes, consider splitting the SCP.

### Strategies for Reducing SCP Size

- **Use wildcards in actions:** `s3:Put*` instead of listing every `s3:Put*` action.
- **Combine similar statements:** If two statements have the same effect and conditions
  but different actions, merge the action lists.
- **Split into multiple SCPs:** Move groups of statements to a new SCP and attach both
  to the same target (up to the 5-SCP limit).
- **Use `NotAction` instead of `Action`:** For allowlist-style policies, `NotAction` can
  be shorter than listing every denied action.
- **Remove redundant conditions:** If every statement has the same exempt-role condition,
  ensure you are not duplicating condition blocks unnecessarily.

---

## Testing Changes Safely

### Strategy 1: Test OU (Recommended)

1. Create a test OU (e.g., `SCP-Testing`) with no production accounts.
2. Move a sandbox account into the test OU.
3. Attach the modified SCP only to the test OU via `scp_attachments`.
4. Verify the SCP works as expected by testing the denied and allowed actions.
5. Once validated, update the attachment to target the production OUs.

### Strategy 2: Dry-Run with IAM Policy Simulator

The IAM Policy Simulator does not evaluate SCPs directly, but you can use Access
Analyzer policy validation:

```bash
# Validate the policy JSON syntax
aws accessanalyzer validate-policy \
  --policy-document file://policy.json \
  --policy-type SERVICE_CONTROL_POLICY
```

This checks for syntax errors, invalid actions, and unsupported condition keys.

### Strategy 3: CloudTrail Dry-Run

1. Apply the SCP with an additional condition that restricts it to a specific test role:

   ```hcl
   condition {
     test     = "ArnLike"
     variable = "aws:PrincipalArn"
     values   = ["arn:aws:iam::*:role/SCP-Test-Role"]
   }
   ```

2. Test actions using the `SCP-Test-Role`.
3. Once validated, remove the test condition and reapply.

### Strategy 4: Plan-Only Validation

At a minimum, always run `terragrunt plan` and review:

- Which policies are being updated.
- The diff of the JSON content (Terraform shows this for `content` changes).
- That no unexpected attachments are being created or destroyed.

---

## Common Modifications

### Add a New Global Service to the Region-Deny Exemption

If a new AWS global service is released, add it to the `not_actions` list in the
`deny-regions` SCP:

```hcl
# In data "aws_iam_policy_document" "deny_regions"
statement {
  not_actions = [
    # ... existing services ...
    "newglobalservice:*",    # <-- Add here, maintain alphabetical order
  ]
}
```

### Add a New Resource Type to Tagging Enforcement

To require tags on additional resource types, update the `actions` list in the
`require-tagging` SCP:

```hcl
dynamic "statement" {
  for_each = var.required_tags
  content {
    actions = [
      "ec2:RunInstances",
      "s3:CreateBucket",
      "rds:CreateDBInstance",
      "lambda:CreateFunction",    # <-- Add new resource types
      "ecs:CreateCluster",
    ]
  }
}
```

### Add an Emergency Exempt Role

In `terragrunt.hcl` — **append to the existing seven entries, do not replace them**:

```hcl
inputs = {
  exempt_roles = [
    "OrganizationAccountAccessRole",
    "github-actions-terratest", # keep — CI tests
    "PlatformDeployer",         # keep — IaC apply
    "crossplane-ecr-provisioner",  # keep — environment ECR provisioning
    "crossplane-provisioner-*",    # keep — environment IAM/EKS provisioning
    "platform-use1-eks-karpenter-*", # keep — Karpenter node provisioning, platform (ADR-078)
    "preprod-use1-eks-karpenter-*",  # keep — Karpenter node provisioning, preprod (ADR-078)
    "BreakGlassRole",           # <-- emergency role being added
  ]
}
```

This is a high-impact change. See `docs/runbooks/incident-scp-blocking.md` for the
emergency procedure and governance requirements.

---

## Pre-Merge Checklist

Before merging SCP changes to `main`:

- [ ] `terragrunt plan` shows only expected changes.
- [ ] All modified SCPs are under 5,120 bytes.
- [ ] No target has more than 5 SCPs attached.
- [ ] The compliance mapping document has been updated.
- [ ] Changes have been tested against a non-production account or OU.
- [ ] Security team has reviewed and approved the change.
- [ ] The PR description explains the business justification for the change.
- [ ] If exempt roles were modified, the change is documented with approval evidence.
