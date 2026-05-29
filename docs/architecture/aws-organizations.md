# AWS Organizations Architecture

This document describes the AWS Organizations structure, Service Control Policies (SCPs),
and security model managed by the `organizations` Terraform module. It is intended for
auditors, new team members, and anyone evaluating the blast radius of changes to the
organization hierarchy or policy set.

All resources described here are defined in infrastructure-as-code and applied through
Terragrunt. No manual console changes are expected or supported.

---

## Table of Contents

1. [Organization Structure](#organization-structure)
2. [SCP Inheritance Model](#scp-inheritance-model)
3. [Data Flow: Terragrunt to AWS API](#data-flow-terragrunt-to-aws-api)
4. [Service Control Policy Catalog](#service-control-policy-catalog)
5. [Security Model and Exempt Roles](#security-model-and-exempt-roles)
6. [SCP Budget Allocation](#scp-budget-allocation)
7. [AWS Service Limits and Constraints](#aws-service-limits-and-constraints)
8. [HIPAA Compliance Extension](#hipaa-compliance-extension)
9. [Operational Runbook Notes](#operational-runbook-notes)

---

## Organization Structure

The organization is rooted in the management account (`<MGMT_ACCOUNT_ID>`). All
Organizational Units (OUs) and member accounts are created declaratively via the
`organizational_units` and `accounts` input maps.

### OU Tree with SCP Attachment Points

```text
Root (r-xxxx)
|
|-- [SCPs attached at root]:
|     * baseline-guardrails
|     * protect-security-services
|     * enforce-encryption
|     * deny-regions
|
|-- OU: Platform
|     |-- [SCPs attached at Platform]:
|     |     * protect-data-and-network
|     |
|     |-- Account: platform (admin+platform@example.com)
|
|-- OU: Workloads
      |-- [SCPs attached at Workloads]:
      |     * protect-data-and-network
      |     * require-tagging
      |     * restrict-iam-users
      |
      |-- OU: Workloads/Preprod
      |     |-- Account: preprod (admin+preprod@example.com)
      |
      |-- OU: Workloads/Prod
      |     |-- (no accounts yet)
      |
      |-- OU: Workloads/Regulated
            |-- (no accounts yet)
```

The management account itself sits at the organization root and is not placed inside
any OU. This is standard AWS practice: SCPs do not restrict the management account
regardless of attachment. All enforcement happens on member accounts only.

### Key Design Decisions

- **Flat top level.** Only two root-level OUs exist: `Platform` (shared infrastructure)
  and `Workloads` (application teams). This avoids deep nesting that complicates SCP
  reasoning.
- **Workload sub-OUs by lifecycle.** `Preprod`, `Prod`, and `Regulated` are nested
  under `Workloads` so they inherit the workload-level SCPs automatically while still
  allowing per-lifecycle overrides later.
- **Regulated OU.** A dedicated OU for accounts that fall under compliance frameworks
  (HIPAA, PCI). The optional `hipaa-eligible-services` SCP can be attached here
  without affecting non-regulated workloads.

---

## SCP Inheritance Model

AWS SCPs use an **intersection (most-restrictive-wins)** evaluation model. An action
is allowed only if every SCP in the chain from root to the target account permits it.
A single Deny at any level in the hierarchy is final and cannot be overridden by an
Allow at a lower level.

### How Policies Compose: Root to OU to Account

```text
                    +------------------+
                    |   Organization   |
                    |      Root        |
                    |                  |
                    | Attached SCPs:   |
                    |  - baseline-     |
                    |    guardrails    |
                    |  - protect-      |
                    |    security-     |
                    |    services      |
                    |  - enforce-      |
                    |    encryption    |
                    |  - deny-regions  |
                    +--------+---------+
                             |
              +--------------+--------------+
              |                             |
    +---------v---------+       +-----------v-----------+
    |   OU: Platform    |       |   OU: Workloads       |
    |                   |       |                       |
    | Attached SCPs:    |       | Attached SCPs:        |
    |  - protect-data-  |       |  - protect-data-      |
    |    and-network    |       |    and-network         |
    +--------+----------+       |  - require-tagging    |
             |                  |  - restrict-iam-users |
             |                  +-----------+-----------+
    +--------v----------+                   |
    | Account: platform |       +-----------+-----------+
    | Effective SCPs:   |       |           |           |
    | (root 4) + (OU 1) |      Preprod    Prod    Regulated
    | = 5 total         |       |
    +-------------------+       |
                       +--------v----------+
                       | Account: preprod  |
                       | Effective SCPs:   |
                       | (root 4)          |
                       |  + (Workloads 3)  |
                       | = 7 total         |
                       +-------------------+
```

### Effective Policy Calculation

For the **platform** account:

| Layer     | SCPs Applied                                                    | Count |
|-----------|-----------------------------------------------------------------|-------|
| Root      | baseline-guardrails, protect-security-services, enforce-encryption, deny-regions | 4 |
| Platform  | protect-data-and-network                                        | 1     |
| **Total** |                                                                 | **5** |

For the **preprod** account:

| Layer      | SCPs Applied                                                    | Count |
|------------|-----------------------------------------------------------------|-------|
| Root       | baseline-guardrails, protect-security-services, enforce-encryption, deny-regions | 4 |
| Workloads  | protect-data-and-network, require-tagging, restrict-iam-users   | 3     |
| **Total**  |                                                                 | **7** |

Any action attempted by a principal in the `preprod` account must be permitted
(or at least not denied) by all 7 policies. The evaluation logic is:

1. Start with the default `FullAWSAccess` policy that AWS attaches to the root.
2. At each level, intersect the previous effective permission set with the policies
   attached at that level.
3. A Deny statement anywhere in the chain is absolute. There is no mechanism to
   "re-allow" a denied action at a lower level.

This means adding a Deny SCP at the root affects every member account in the
organization, while attaching an SCP at the `Workloads` OU affects only accounts
under that OU (and its children).

---

## Data Flow: Terragrunt to AWS API

This section traces how a configuration change in Terragrunt flows through the module
to become AWS API calls.

### Step 1: Terragrunt Input Resolution

```text
infra/live/aws/mgmt/global/organizations/terragrunt.hcl
    |
    |-- include "base" --> aws/_base.hcl
    |       |-- reads env.hcl       (mgmt/common.hcl: account_id, env)
    |       |-- reads region.hcl    (global: region = us-east-1)
    |       |-- reads network.hcl   (global: empty)
    |       |-- reads workload.hcl  (management workload, standard tier)
    |       |-- reads common.hcl    (AWS cloud-wide tags, account map)
    |       |-- reads _versions.hcl (module source paths)
    |       |-- composes tags: common -> env -> region -> workload
    |       |-- runs safety assertions (env path, account ID)
    |
    |-- include "root" --> infra/root.hcl
    |       |-- detects cloud = "aws" from path
    |       |-- configures S3 backend (bucket: tfstate-mgmt-<MGMT_ACCOUNT_ID>)
    |       |-- generates provider_aws.tf (region: us-east-1)
    |       |-- generates versions.tf (AWS provider 5.91.0)
    |
    |-- terraform.source = module_source.organizations
    |       resolved to: {repo_root}/infra/modules/aws//organizations
    |
    |-- inputs = {
    |     create              = true
    |     create_organization = true
    |     tags                = <composed tags from _base.hcl>
    |     allowed_regions     = ["us-east-1", "us-west-2"]
    |     required_tags       = ["Environment", "ManagedBy", "Owner"]
    |     organizational_units = { ... 5 OUs ... }
    |     accounts             = { ... 2 accounts ... }
    |   }
```

### Step 2: Module Processing

Inside `infra/modules/aws/organizations/main.tf`, the inputs drive resource creation:

```text
inputs.create = true
inputs.create_organization = true
    |
    +--> aws_organizations_organization.this[0]
    |      feature_set = "ALL"
    |      enabled_policy_types = ["SERVICE_CONTROL_POLICY", "TAG_POLICY"]
    |      service_access_principals = [cloudtrail, config, guardduty, ...]
    |      lifecycle { prevent_destroy = true }
    |
    +--> Resolves root_id from organization.roots[0].id
    |
    +--> For each entry in inputs.organizational_units:
    |      aws_organizations_organizational_unit.this["Platform"]
    |        parent_id = root_id (parent = null)
    |      aws_organizations_organizational_unit.this["Workloads"]
    |        parent_id = root_id (parent = null)
    |      aws_organizations_organizational_unit.this["Workloads/Preprod"]
    |        parent_id = OU["Workloads"].id
    |      aws_organizations_organizational_unit.this["Workloads/Prod"]
    |        parent_id = OU["Workloads"].id
    |      aws_organizations_organizational_unit.this["Workloads/Regulated"]
    |        parent_id = OU["Workloads"].id
    |
    +--> For each entry in inputs.accounts:
    |      aws_organizations_account.this["platform"]
    |        email     = admin+platform@example.com
    |        parent_id = OU["Platform"].id
    |      aws_organizations_account.this["preprod"]
    |        email     = admin+preprod@example.com
    |        parent_id = OU["Workloads/Preprod"].id
    |
    +--> Builds default SCP JSON from data sources (scps.tf)
    |      7 default SCPs + 1 optional HIPAA SCP
    |
    +--> For each SCP in effective_scps:
    |      aws_organizations_policy.this["baseline-guardrails"]
    |      aws_organizations_policy.this["protect-security-services"]
    |      ... (one per SCP)
    |
    +--> Flattens scp_attachments into (target, policy) pairs:
           aws_organizations_policy_attachment.this["root/baseline-guardrails"]
           aws_organizations_policy_attachment.this["root/protect-security-services"]
           aws_organizations_policy_attachment.this["root/enforce-encryption"]
           aws_organizations_policy_attachment.this["root/deny-regions"]
           aws_organizations_policy_attachment.this["Platform/protect-data-and-network"]
           aws_organizations_policy_attachment.this["Workloads/protect-data-and-network"]
           aws_organizations_policy_attachment.this["Workloads/require-tagging"]
           aws_organizations_policy_attachment.this["Workloads/restrict-iam-users"]
```

### Step 3: AWS API Calls

OpenTofu translates the plan into AWS Organizations API calls:

| Resource Type                        | API Call                          | Idempotent? |
|--------------------------------------|-----------------------------------|-------------|
| `aws_organizations_organization`     | `CreateOrganization`              | Yes (one per account) |
| `aws_organizations_organizational_unit` | `CreateOrganizationalUnit`     | No (creates duplicate if name reused) |
| `aws_organizations_account`          | `CreateAccount`                   | No (async, creates new account) |
| `aws_organizations_policy`           | `CreatePolicy` / `UpdatePolicy`   | Yes (update by ID) |
| `aws_organizations_policy_attachment`| `AttachPolicy`                    | Yes (no-op if already attached) |

Both the organization and OUs have `lifecycle { prevent_destroy = true }` to guard
against accidental deletion. Account resources use `lifecycle { ignore_changes = [role_name] }`
because AWS sets the role name during account creation and it should not be modified
after the fact.

---

## Service Control Policy Catalog

### SCP 1: baseline-guardrails

**Purpose:** Protect the integrity of the organization itself and the management
account boundary. This is the foundational policy that prevents accounts from
escaping the organization or abusing root credentials.

| Statement ID               | What It Denies                                      | Exempt? |
|-----------------------------|-----------------------------------------------------|---------|
| DenyLeaveOrganization       | `organizations:LeaveOrganization`                   | No      |
| DenyRootUserActions         | All actions except `sts:GetSessionToken` for root   | No      |
| DenyRootAccessKeys          | `iam:CreateAccessKey` for root user                 | No      |
| DenyRegionChanges           | `account:EnableRegion`, `account:DisableRegion`     | Yes     |
| DenyPasswordPolicyChanges   | `iam:DeleteAccountPasswordPolicy`, `iam:UpdateAccountPasswordPolicy` | Yes |
| ProtectOrganizationRole     | Modification of `OrganizationAccountAccessRole`     | Yes     |

**Why it matters:** Without this SCP, a compromised account administrator could
remove the account from the organization, effectively removing all SCP controls.
The root user lockout prevents the single most dangerous credential in any account
from being used for day-to-day operations.

### SCP 2: protect-security-services

**Purpose:** Prevent tampering with audit and detection infrastructure. Even if an
attacker gains admin access in a member account, they cannot silence the security
tooling that would detect their activity.

| Statement ID          | What It Denies                                               | Exempt? |
|-----------------------|--------------------------------------------------------------|---------|
| ProtectCloudTrail     | Stop/Delete/Update trail, modify event selectors             | Yes     |
| ProtectConfig         | Stop/Delete configuration recorder, delete delivery channel  | Yes     |
| ProtectGuardDuty      | Delete detector, disassociate from master, stop monitoring   | Yes     |
| ProtectSecurityHub    | Disable hub, disable standards, delete/disassociate members  | Yes     |
| ProtectAccessAnalyzer | Delete analyzer                                              | Yes     |
| ProtectFlowLogs       | Delete VPC flow logs                                         | Yes     |

**Why it matters:** These services form the detection layer of the security model.
CloudTrail provides the audit log, GuardDuty provides threat detection, Config
provides configuration compliance, and SecurityHub aggregates findings. Disabling
any of them creates a blind spot.

### SCP 3: enforce-encryption

**Purpose:** Ensure encryption at rest is non-negotiable and that EC2 instances
use the more secure IMDSv2 metadata service.

| Statement ID            | What It Denies                                      | Exempt? |
|--------------------------|-----------------------------------------------------|---------|
| DenyDisableEbsDefault    | Disabling default EBS encryption                    | Yes     |
| DenyUnencryptedVolumes   | Creating unencrypted EBS volumes                    | No      |
| DenyUnencryptedRds       | Creating unencrypted RDS instances                  | No      |
| DenyUnencryptedRdsCluster| Creating unencrypted RDS clusters                   | No      |
| ProtectKmsKeys           | Scheduling key deletion or disabling keys           | Yes     |
| EnforceIMDSv2            | Launching instances without IMDSv2 (`HttpTokens != required`) | No |

**Why it matters:** Encryption at rest is a baseline requirement for most compliance
frameworks. The IMDSv2 enforcement prevents SSRF-based credential theft attacks
that exploit the IMDSv1 endpoint.

### SCP 4: deny-regions

**Purpose:** Restrict resource creation to approved AWS regions (`us-east-1` and
`us-west-2`), preventing shadow infrastructure in regions the team does not monitor.

| Statement ID           | What It Denies                                     | Exempt? |
|-------------------------|----------------------------------------------------|---------|
| DenyNonAllowedRegions   | All regional actions outside allowed regions       | Yes     |

**Global service exemptions** (these services operate outside any single region and
must be excluded from region deny):

| Category          | Services                                                      |
|-------------------|---------------------------------------------------------------|
| Identity          | `iam:*`, `sts:*`, `sso:*`                                    |
| Organization      | `organizations:*`                                             |
| DNS/CDN           | `route53:*`, `route53domains:*`, `cloudfront:*`               |
| Security (global) | `waf:*`, `wafv2:*`, `waf-regional:*`, `shield:*`, `access-analyzer:*` |
| Networking        | `globalaccelerator:*`                                         |
| Support/Health    | `support:*`, `health:*`, `trustedadvisor:*`                   |
| Billing/Cost      | `ce:*`, `cur:*`, `budgets:*`, `billing:*`, `account:*`, `pricing:*`, `tax:*`, `freetier:*`, `invoicing:*`, `payments:*`, `savingsplans:*` |
| Governance        | `tag:*`, `artifact:*`                                         |

**Why it matters:** An attacker who gains access to an account could spin up
resources in a region the team never checks (e.g., `ap-southeast-1`). Region
restriction limits the blast radius and simplifies monitoring.

### SCP 5: protect-data-and-network

**Purpose:** Prevent public data exposure and unauthorized network changes.

| Statement ID               | What It Denies                                   | Exempt? |
|-----------------------------|--------------------------------------------------|---------|
| ProtectS3PublicAccessBlock  | Removing S3 public access block settings         | Yes     |
| DenyDefaultVpc              | Creating default VPCs or subnets                 | Yes     |
| DenyExternalSharing         | RAM shares that allow external principals        | Yes     |
| ProtectBackups              | Deleting Glacier archives, Backup vaults/plans/recovery points | Yes |

**Why it matters:** Public S3 buckets are one of the most common sources of cloud
data breaches. Default VPCs have overly permissive default security groups. RAM
external sharing could leak resources to accounts outside the organization.

### SCP 6: require-tagging

**Purpose:** Enforce that key resources carry mandatory tags at creation time.
The required tags are driven by the `required_tags` variable (default:
`Environment`, `ManagedBy`, `Owner`).

| Statement ID                            | What It Denies                         | Exempt? |
|------------------------------------------|----------------------------------------|---------|
| RequireTagEnvironment (dynamic)          | Creating EC2, S3, RDS without tag      | Yes     |
| RequireTagManagedBy (dynamic)            | Creating EC2, S3, RDS without tag      | Yes     |
| RequireTagOwner (dynamic)               | Creating EC2, S3, RDS without tag      | Yes     |

The SCP uses a `dynamic` block to generate one statement per required tag. Each
statement denies `ec2:RunInstances`, `s3:CreateBucket`, and `rds:CreateDBInstance`
when the respective `aws:RequestTag/{TagKey}` is null.

**Why it matters:** Tags are the foundation of cost allocation, access control
(ABAC), and operational visibility. Resources created without tags become orphaned
and impossible to attribute.

### SCP 7: restrict-iam-users

**Purpose:** Force all human access through federated identity (AWS SSO / IAM
Identity Center) by preventing the creation of IAM users and long-lived credentials.

| Statement ID              | What It Denies                                    | Exempt? |
|----------------------------|---------------------------------------------------|---------|
| DenyIamUserCreation        | `iam:CreateUser`, `iam:CreateLoginProfile`, `iam:CreateAccessKey` | Yes |
| DenyUserPolicyAttachment   | `iam:AttachUserPolicy`, `iam:PutUserPolicy`       | Yes     |

**Why it matters:** IAM users with long-lived access keys are the primary vector
for credential leaks. Federated access provides centralized MFA enforcement,
session time limits, and a single point of revocation.

### SCP 8: hipaa-eligible-services (optional)

**Purpose:** When enabled (`enable_hipaa_scp = true`), restricts accounts to only
those AWS services that appear on the HIPAA Eligible Services list. This is a
service-level allowlist using `NotAction`.

This SCP is not enabled by default. It is intended for attachment to the
`Workloads/Regulated` OU when accounts in that OU handle protected health
information (PHI).

---

## Security Model and Exempt Roles

### The Exempt Role Mechanism

Every Deny statement that could block legitimate administrative operations includes
a condition that exempts specific IAM roles:

```hcl
condition {
  test     = "ArnNotLike"
  variable = "aws:PrincipalArn"
  values   = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
}
```

The default exempt role is `OrganizationAccountAccessRole`, which is the role AWS
automatically creates in member accounts during account creation. It is assumable
from the management account.

### What Exempt Roles CAN Bypass

Exempt roles can bypass the deny conditions on statements that include the
`ArnNotLike` condition. These are administrative operations that may be necessary
for infrastructure management:

- Modifying region settings, password policies
- Managing CloudTrail, Config, GuardDuty, SecurityHub, Access Analyzer configuration
- Disabling EBS default encryption, managing KMS keys
- Operating in non-allowed regions
- Modifying S3 public access blocks, creating default VPCs
- Creating IAM users (for service accounts if absolutely necessary)
- Creating resources without required tags
- Managing RAM shares, backups

### What Exempt Roles CANNOT Bypass

Three statements have **no exemption condition** and apply universally, even to
the exempt role:

| Statement                   | Why No Exemption                                       |
|-----------------------------|--------------------------------------------------------|
| DenyLeaveOrganization       | No legitimate reason for any role to remove an account from the org |
| DenyRootUserActions         | Root user should never be used; this is a hard lockout |
| DenyRootAccessKeys          | Root access keys should never exist                    |
| DenyUnencryptedVolumes      | Encryption has no legitimate bypass case               |
| DenyUnencryptedRds          | Same as above                                          |
| DenyUnencryptedRdsCluster   | Same as above                                          |
| EnforceIMDSv2               | IMDSv2 has no legitimate bypass case                   |

### Blast Radius Analysis

| Scenario                                    | Blast Radius                          |
|---------------------------------------------|---------------------------------------|
| Exempt role credentials compromised         | All member accounts (role exists in every account). Attacker can disable security services, modify network controls, and create IAM users. Cannot leave org or use root. |
| Root SCP modified (e.g., remove deny-regions)| All member accounts lose region restriction immediately. |
| OU-level SCP removed (e.g., from Workloads) | All accounts under that OU and its children. Platform OU unaffected. |
| New account added to wrong OU               | Account inherits the wrong SCP set. Safety assertions in `_base.hcl` help prevent this at the Terragrunt layer. |
| Management account compromise               | Full organization control. SCPs do not restrict the management account. This is the highest-impact scenario. |

### Mitigations

- The management account should have minimal workloads (only the organization module itself).
- `prevent_destroy = true` on the organization and OUs prevents accidental Terraform-driven deletion.
- The `environment_account_map` in `common.hcl` provides a cross-check that prevents
  deploying to the wrong account.
- All changes go through code review via the Terragrunt/IaC pipeline.

---

## SCP Budget Allocation

AWS enforces hard limits on SCPs. Understanding current consumption is critical
before adding new policies.

### Limits Reference

| Limit                                   | Value   |
|-----------------------------------------|---------|
| Maximum SCPs per target (root, OU, account) | 5   |
| Maximum SCP document size               | 5,120 bytes |
| Maximum SCPs per organization           | 1,000   |
| Maximum nesting depth for OUs           | 5       |

### Current SCP Attachment Count Per Target

| Target                | Attached SCPs                                                                                   | Count | Remaining |
|-----------------------|-------------------------------------------------------------------------------------------------|-------|-----------|
| Root                  | baseline-guardrails, protect-security-services, enforce-encryption, deny-regions                 | 4     | 1         |
| Platform OU           | protect-data-and-network                                                                        | 1     | 4         |
| Workloads OU          | protect-data-and-network, require-tagging, restrict-iam-users                                   | 3     | 2         |
| Workloads/Preprod OU  | (none directly; inherits from Workloads and Root)                                               | 0     | 5         |
| Workloads/Prod OU     | (none directly; inherits from Workloads and Root)                                               | 0     | 5         |
| Workloads/Regulated OU| (none directly; future: hipaa-eligible-services)                                                | 0     | 5         |

**Key observation:** The **root** target has only **1 slot remaining**. Any new
organization-wide SCP will require either consolidating existing root SCPs or
attaching the new policy at the OU level instead.

### SCP Document Size Considerations

The 5,120-byte limit per SCP document is the most common reason SCPs need to be
split. The largest policies in this module are:

- **deny-regions**: Contains a long `not_actions` list for global service exemptions.
  This can grow as AWS adds new global services.
- **hipaa-eligible-services**: Contains the full HIPAA-eligible service allowlist
  (70+ services). This is the largest single SCP and may approach the byte limit
  as AWS adds new HIPAA-eligible services.
- **require-tagging**: Grows linearly with the number of required tags (one
  statement per tag).

When approaching the 5,120-byte limit, consider:

1. Splitting the SCP into two policies (uses an additional attachment slot).
2. Reducing whitespace (Terraform's `jsonencode` is already compact).
3. Using wildcards in action lists where safe (e.g., `s3:Put*` instead of
   listing every Put action).

---

## AWS Service Limits and Constraints

### Organization Service Integration

The module enables the following AWS services for organization-wide integration
via `aws_service_access_principals`:

| Service Principal                        | Purpose                                    |
|------------------------------------------|--------------------------------------------|
| `cloudtrail.amazonaws.com`               | Organization-wide trail                    |
| `config.amazonaws.com`                   | Multi-account Config aggregation           |
| `guardduty.amazonaws.com`                | Delegated administrator for threat detection|
| `securityhub.amazonaws.com`              | Centralized security findings              |
| `access-analyzer.amazonaws.com`          | Cross-account access analysis              |
| `sso.amazonaws.com`                      | IAM Identity Center (SSO)                  |
| `tagpolicies.tag.amazonaws.com`          | Organization-wide tag policies             |

### Enabled Policy Types

| Policy Type              | Purpose                                           |
|--------------------------|---------------------------------------------------|
| SERVICE_CONTROL_POLICY   | Permission guardrails (the SCPs described above)  |
| TAG_POLICY               | Tag standardization and enforcement               |

### Region Restrictions

Allowed regions: `us-east-1`, `us-west-2`

All other regions are denied for regional services. Global services (IAM, STS,
Route 53, CloudFront, WAF, Shield, billing, support, etc.) are explicitly
exempted and continue to work regardless of region restrictions.

---

## HIPAA Compliance Extension

The optional HIPAA SCP (`enable_hipaa_scp = true`) implements a service-level
allowlist. When enabled, it denies access to any AWS service not on the
HIPAA Eligible Services list.

### Intended Usage

1. Enable the variable: `enable_hipaa_scp = true` in the module inputs.
2. Add `"hipaa-eligible-services"` to the `scp_attachments` for the
   `Workloads/Regulated` OU.
3. Only accounts placed under `Workloads/Regulated` will be restricted.

### Impact Assessment

- The allowlist contains approximately 90 services.
- Newer AWS services that are HIPAA-eligible but not yet in the list will be
  blocked until the list is updated.
- The exempt role can bypass this restriction for administrative operations.

---

## Operational Runbook Notes

### Adding a New Account

1. Add the account to the `accounts` map in
   `infra/live/aws/mgmt/global/organizations/terragrunt.hcl`.
2. Specify the target OU. The account will inherit all SCPs from the root down to
   its OU.
3. Run `terragrunt plan` to verify. Account creation is asynchronous in AWS; the
   API call returns immediately but the account may take minutes to become usable.
4. The `close_on_deletion = false` setting means removing an account from Terraform
   state does not close the AWS account.

### Adding a New OU

1. Add the OU to the `organizational_units` map with the appropriate `parent`.
2. If the OU needs SCPs beyond those inherited from its parent, add entries to
   `scp_attachments` in `variables.tf` (default) or override in the Terragrunt
   inputs.
3. Remember the 5-SCP-per-target limit when planning attachments.

### Adding a New SCP

1. Add the policy document as a new `data "aws_iam_policy_document"` block in
   `scps.tf`.
2. Add it to the `default_scps` local in `main.tf`.
3. Add the attachment mapping in the `scp_attachments` variable default or
   override it in Terragrunt inputs.
4. Verify the target will not exceed 5 attached SCPs.
5. Verify the policy document is under 5,120 bytes.

### Emergency: Bypassing an SCP

If an SCP is blocking a legitimate operation and the exempt role is not available:

1. The operation must be performed from the **management account**, which is not
   subject to SCPs.
2. Alternatively, temporarily detach the SCP from the target. This requires
   management account credentials and should be done through the IaC pipeline,
   not the console.
3. All emergency changes must be backported to code immediately to avoid drift.
