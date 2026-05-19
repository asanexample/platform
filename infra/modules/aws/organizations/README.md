# AWS Organizations Module

This module manages an AWS Organizations hierarchy including the organization
itself, organizational units (OUs), member accounts, and Service Control
Policies (SCPs). It provides a comprehensive, opinionated set of security
guardrails out of the box while allowing full customization through input
variables.

---

## Overview

The module operates in two modes:

- **Greenfield** (`create_organization = true`): Creates a new AWS Organization
  with all features enabled, including service integrations for CloudTrail,
  Config, GuardDuty, Security Hub, IAM Access Analyzer, SSO, and tag policies.

- **Brownfield** (`create_organization = false`): Data-sources an existing AWS
  Organization and manages OUs, accounts, and SCPs within it.

In both modes, the module creates organizational units with support for nesting,
provisions member accounts into specific OUs, generates seven built-in SCPs
from policy documents, and attaches those SCPs to OUs and the organization root
based on a configurable attachment map.

---

## Usage

### Minimal Configuration

This example data-sources an existing organization and creates a flat OU
structure with one account:

```hcl
module "organizations" {
  source = "../../modules/aws/organizations"

  create              = true
  create_organization = false
  tags                = { ManagedBy = "Terragrunt" }

  organizational_units = {
    "Platform"  = { parent = null }
    "Workloads" = { parent = null }
  }

  accounts = {
    "platform" = { email = "aws+platform@example.com", ou = "Platform" }
  }
}
```

### Full Configuration

This example creates a new organization with nested OUs, multiple accounts,
custom region restrictions, required tags, HIPAA compliance, and an additional
exempt role:

```hcl
module "organizations" {
  source = "../../modules/aws/organizations"

  create              = true
  create_organization = true
  tags = {
    ManagedBy   = "Terragrunt"
    Environment = "mgmt"
    Owner       = "Platform Team"
  }

  # Region restrictions
  allowed_regions = ["us-east-1", "us-west-2", "eu-west-1"]

  # Tag enforcement
  required_tags = ["Environment", "ManagedBy", "Owner", "CostCenter"]

  # Exempt roles (bypass SCP denies)
  exempt_roles = ["OrganizationAccountAccessRole", "BreakGlassRole"]

  # HIPAA eligible services allowlist
  enable_hipaa_scp = true

  # Service integrations
  organization_aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "guardduty.amazonaws.com",
    "securityhub.amazonaws.com",
    "access-analyzer.amazonaws.com",
    "sso.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
  ]

  organization_enabled_policy_types = ["SERVICE_CONTROL_POLICY", "TAG_POLICY"]

  # Organizational units (nested via parent references)
  organizational_units = {
    "Platform"            = { parent = null }
    "Workloads"           = { parent = null }
    "Workloads/Preprod"   = { parent = "Workloads" }
    "Workloads/Prod"      = { parent = "Workloads" }
    "Workloads/Regulated" = { parent = "Workloads" }
    "Sandbox"             = { parent = null }
  }

  # Member accounts
  accounts = {
    "platform" = { email = "aws+platform@example.com", ou = "Platform" }
    "preprod"  = { email = "aws+preprod@example.com",  ou = "Workloads/Preprod" }
    "prod"     = { email = "aws+prod@example.com",     ou = "Workloads/Prod" }
    "sandbox"  = { email = "aws+sandbox@example.com",  ou = "Sandbox" }
  }

  # SCP attachment map (target -> list of SCP names)
  scp_attachments = {
    "root"                = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
    "Platform"            = ["protect-data-and-network"]
    "Workloads"           = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
    "Workloads/Regulated" = ["hipaa-eligible-services"]
    "Sandbox"             = ["baseline-guardrails", "deny-regions"]
  }
}
```

---

## Variables

| Variable | Type | Default | Required | Description |
|----------|------|---------|----------|-------------|
| `create` | `bool` | `true` | No | Whether to create any resources in this module. Set to `false` to disable entirely. |
| `create_organization` | `bool` | `false` | No | Whether to create the AWS Organization. Set to `false` to data-source an existing one. |
| `organization_aws_service_access_principals` | `list(string)` | `["cloudtrail.amazonaws.com", "config.amazonaws.com", "guardduty.amazonaws.com", "securityhub.amazonaws.com", "access-analyzer.amazonaws.com", "sso.amazonaws.com", "tagpolicies.tag.amazonaws.com"]` | No | AWS service principals to enable for organization integration. Only used when `create_organization = true`. |
| `organization_enabled_policy_types` | `list(string)` | `["SERVICE_CONTROL_POLICY", "TAG_POLICY"]` | No | Policy types to enable in the organization. Only used when `create_organization = true`. |
| `organizational_units` | `map(object({parent = optional(string)}))` | `{}` | No | Map of OU names to configuration. Key is the OU name. Set `parent = null` for root-level OUs, or reference another OU key for nesting. |
| `accounts` | `map(object({email = string, ou = optional(string)}))` | `{}` | No | Map of account names to configuration. `email` is required and must be unique across AWS. `ou` references a key in `organizational_units`; omit or set to `null` to place the account at the root. |
| `service_control_policies` | `map(string)` | `null` | No | Custom SCP JSON map. When non-null, **replaces all built-in SCPs**. Keys are policy names, values are JSON policy documents. |
| `scp_attachments` | `map(list(string))` | See below | No | Map of target name to list of SCP names. Use `"root"` for the org root; other keys must match OU names from `organizational_units`. |
| `allowed_regions` | `list(string)` | `["us-east-1", "us-west-2"]` | No | AWS regions where resources are allowed. Global services (IAM, Route 53, CloudFront, etc.) are always exempt. |
| `required_tags` | `list(string)` | `["Environment", "ManagedBy", "Owner"]` | No | Tag keys enforced on EC2 instances, S3 buckets, and RDS instances via the `require-tagging` SCP. |
| `exempt_roles` | `list(string)` | `["OrganizationAccountAccessRole"]` | No | IAM role names exempt from SCP deny statements. Converted to wildcard ARN patterns (`arn:aws:iam::*:role/<name>`). |
| `enable_hipaa_scp` | `bool` | `false` | No | Enable the HIPAA eligible services allowlist SCP. Must also be referenced in `scp_attachments` to take effect. |
| `tags` | `map(string)` | `{}` | No | Tags applied to SCPs and OUs. |

**Default `scp_attachments`:**

```hcl
{
  "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
  "Platform"  = ["protect-data-and-network"]
  "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
}
```

---

## Outputs

| Output | Type | Description |
|--------|------|-------------|
| `organization_id` | `string` | The ID of the AWS Organization (e.g., `o-a4kjvito7o`). |
| `organization_arn` | `string` | The ARN of the AWS Organization. |
| `root_id` | `string` | The ID of the organization root. |
| `ou_ids` | `map(string)` | Map of OU names to their IDs. |
| `ou_arns` | `map(string)` | Map of OU names to their ARNs. |
| `account_ids` | `map(string)` | Map of account names to their account IDs. |
| `account_arns` | `map(string)` | Map of account names to their ARNs. |
| `scp_ids` | `map(string)` | Map of SCP names to their policy IDs. |

---

## Service Control Policy Reference

The module includes seven built-in SCPs (plus one optional HIPAA SCP). All
built-in SCPs exempt the roles listed in `var.exempt_roles` from their deny
statements.

### baseline-guardrails

**Purpose:** Foundational account and identity protection.

| Statement | Effect | What It Prevents |
|-----------|--------|-----------------|
| DenyLeaveOrganization | Deny | Accounts leaving the organization |
| DenyRootUserActions | Deny | All root user actions except `sts:GetSessionToken` |
| DenyRootAccessKeys | Deny | Creating access keys for the root user |
| DenyRegionChanges | Deny | Enabling or disabling AWS regions |
| DenyPasswordPolicyChanges | Deny | Modifying or deleting the account password policy |
| ProtectOrganizationRole | Deny | Modifying the `OrganizationAccountAccessRole` |

**Compliance:** CIS AWS Foundations Benchmark 1.1, 1.4, 1.5; AWS Well-Architected Security Pillar SEC-1.

### protect-security-services

**Purpose:** Prevent tampering with security monitoring and audit trail services.

| Statement | Effect | What It Prevents |
|-----------|--------|-----------------|
| ProtectCloudTrail | Deny | Stopping, deleting, or modifying CloudTrail trails |
| ProtectConfig | Deny | Stopping or deleting AWS Config recorders and delivery channels |
| ProtectGuardDuty | Deny | Deleting or disabling GuardDuty detectors |
| ProtectSecurityHub | Deny | Disabling Security Hub or removing standards/members |
| ProtectAccessAnalyzer | Deny | Deleting IAM Access Analyzer analyzers |
| ProtectFlowLogs | Deny | Deleting VPC flow logs |

**Compliance:** CIS AWS Foundations 2.1, 2.5, 2.6; SOC 2 CC6.1, CC7.2; NIST 800-53 AU-2, AU-6, SI-4.

### enforce-encryption

**Purpose:** Enforce encryption at rest and secure instance configurations.

| Statement | Effect | What It Prevents |
|-----------|--------|-----------------|
| DenyDisableEbsDefault | Deny | Disabling default EBS encryption |
| DenyUnencryptedVolumes | Deny | Creating unencrypted EBS volumes |
| DenyUnencryptedRds | Deny | Creating unencrypted RDS instances |
| DenyUnencryptedRdsCluster | Deny | Creating unencrypted RDS clusters |
| ProtectKmsKeys | Deny | Scheduling KMS key deletion or disabling keys |
| EnforceIMDSv2 | Deny | Launching EC2 instances without IMDSv2 (HttpTokens=required) |

**Compliance:** CIS AWS Foundations 2.2.1; SOC 2 CC6.1; NIST 800-53 SC-28; HIPAA 164.312(a)(2)(iv).

### deny-regions

**Purpose:** Restrict resource creation to approved regions only.

Denies all actions outside `var.allowed_regions`, with exemptions for global
services: IAM, STS, Organizations, Route 53, CloudFront, WAF, Shield, Global
Accelerator, Support, Health, Cost Explorer, Budgets, Billing, Access Analyzer,
Trusted Advisor, SSO, and others.

**Compliance:** Data residency requirements; SOC 2 CC6.6; GDPR Article 44 (when restricted to EU regions).

### protect-data-and-network

**Purpose:** Prevent public exposure of data and network resources.

| Statement | Effect | What It Prevents |
|-----------|--------|-----------------|
| ProtectS3PublicAccessBlock | Deny | Removing S3 public access blocks (account or bucket level) |
| DenyDefaultVpc | Deny | Creating default VPCs or subnets |
| DenyExternalSharing | Deny | Creating RAM resource shares with external principals |
| ProtectBackups | Deny | Deleting Glacier archives, Backup vaults, plans, or recovery points |

**Compliance:** CIS AWS Foundations 2.1.5; SOC 2 CC6.1, CC6.6; AWS Well-Architected SEC-9.

### require-tagging

**Purpose:** Enforce mandatory tags on resource creation.

Dynamically generates one deny statement per tag in `var.required_tags`. Each
statement denies `ec2:RunInstances`, `s3:CreateBucket`, and
`rds:CreateDBInstance` when the specified tag is missing from the request.

Default required tags: `Environment`, `ManagedBy`, `Owner`.

**Compliance:** AWS Well-Architected COST-2; FinOps Foundation tagging best practices.

### restrict-iam-users

**Purpose:** Force the use of federated identities (SSO/roles) instead of IAM users.

| Statement | Effect | What It Prevents |
|-----------|--------|-----------------|
| DenyIamUserCreation | Deny | Creating IAM users, login profiles, or access keys |
| DenyUserPolicyAttachment | Deny | Attaching policies directly to IAM users |

**Compliance:** CIS AWS Foundations 1.16; SOC 2 CC6.1; NIST 800-53 AC-2.

### hipaa-eligible-services (optional)

**Purpose:** Restrict the organization to only HIPAA eligible AWS services.

Enabled by setting `enable_hipaa_scp = true`. Uses a `NotAction` allowlist
pattern: all AWS actions are denied except those from HIPAA eligible services.
The allowlist includes approximately 100 services (EC2, S3, RDS, Lambda, EKS,
and many others).

**Compliance:** HIPAA 164.312; AWS BAA coverage requirements.

---

## Requirements

### Provider Versions

| Provider | Version | Source |
|----------|---------|--------|
| `aws` | `>= 5.91.0` | `hashicorp/aws` |

The provider version is pinned in the root `terragrunt.hcl` via the generated
`versions.tf` file.

### IAM Permissions

The following IAM permissions are required for the principal running this
module:

**For `create_organization = true`:**

- `organizations:CreateOrganization`
- `organizations:EnableAWSServiceAccess`
- `organizations:EnablePolicyType`

**For all deployments:**

- `organizations:DescribeOrganization`
- `organizations:ListRoots`
- `organizations:CreateOrganizationalUnit`
- `organizations:UpdateOrganizationalUnit`
- `organizations:DescribeOrganizationalUnit`
- `organizations:ListOrganizationalUnitsForParent`
- `organizations:CreateAccount`
- `organizations:DescribeAccount`
- `organizations:MoveAccount`
- `organizations:ListAccounts`
- `organizations:CreatePolicy`
- `organizations:UpdatePolicy`
- `organizations:DeletePolicy`
- `organizations:DescribePolicy`
- `organizations:ListPolicies`
- `organizations:AttachPolicy`
- `organizations:DetachPolicy`
- `organizations:ListTargetsForPolicy`
- `organizations:TagResource`
- `organizations:UntagResource`

The `OrganizationAccountAccessRole` (the default exempt role) satisfies all
of these requirements.

---

## Brownfield Deployment

To adopt an existing AWS Organization, set `create_organization = false` and
import existing resources into state.

### Step 1: Gather Existing IDs

```bash
# Organization and root
aws organizations describe-organization
aws organizations list-roots

# OUs (repeat for each level of nesting)
ROOT_ID=$(aws organizations list-roots --query 'Roots[0].Id' --output text)
aws organizations list-organizational-units-for-parent --parent-id "$ROOT_ID"

# Accounts
aws organizations list-accounts

# Existing SCPs
aws organizations list-policies --filter SERVICE_CONTROL_POLICY
```

### Step 2: Import Resources

```bash
cd infra/live/aws/mgmt/global/organizations
terragrunt init

# Import OUs (use actual OU IDs from Step 1)
terragrunt import 'aws_organizations_organizational_unit.this["Platform"]' ou-xxxx-xxxxxxxx
terragrunt import 'aws_organizations_organizational_unit.this["Workloads"]' ou-xxxx-yyyyyyyy
terragrunt import 'aws_organizations_organizational_unit.this["Workloads/Preprod"]' ou-xxxx-zzzzzzzz
terragrunt import 'aws_organizations_organizational_unit.this["Workloads/Prod"]' ou-xxxx-wwwwwwww
terragrunt import 'aws_organizations_organizational_unit.this["Workloads/Regulated"]' ou-xxxx-vvvvvvvv

# Import accounts (use actual account IDs)
terragrunt import 'aws_organizations_account.this["platform"]' 829808296602
terragrunt import 'aws_organizations_account.this["preprod"]' 620830101009
```

### Step 3: Verify and Apply

```bash
# Plan should show zero create/destroy for imported resources
terragrunt plan

# Apply to reconcile tags, SCPs, and attachments
terragrunt apply
```

---

## Lifecycle Protections

The following resources have `prevent_destroy = true` lifecycle rules:

- `aws_organizations_organization.this` -- Destroying an organization is
  irreversible and affects all member accounts.
- `aws_organizations_organizational_unit.this` -- Destroying an OU moves all
  accounts to the root, which changes their effective SCPs.

Account resources have `ignore_changes = [role_name]` to prevent drift
detection on the initial role name, which cannot be changed after creation.

---

## Design Decisions

- **SCPs are generated from `aws_iam_policy_document` data sources** rather than
  raw JSON strings. This provides syntax validation at plan time and enables
  dynamic construction (e.g., the `require-tagging` SCP generates statements
  from the `required_tags` variable).

- **The `service_control_policies` variable replaces all built-in SCPs** when
  set. This is an all-or-nothing override to prevent confusion about which
  policies are active. If you need to add one policy, extend the module instead.

- **OU nesting uses a `parent` reference** to other keys in the same map. This
  avoids a separate variable for hierarchy depth and supports arbitrary nesting
  levels.

- **Accounts have `close_on_deletion = false`** as a safety measure. Removing
  an account from configuration removes it from Terragrunt state but does not
  close the AWS account.
