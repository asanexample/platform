# ADR-003: Service Control Policy Design Philosophy

**Date:** 2025-05-15

**Status:** Accepted

## Context

AWS Organizations Service Control Policies (SCPs) are the primary preventive control mechanism for
a multi-account AWS environment. SCPs define the maximum available permissions for accounts within
an organizational unit (OU) or individually. They do not grant permissions; they constrain them.
Getting the SCP strategy wrong has severe consequences: too restrictive and legitimate workloads
break; too permissive and the guardrails provide false assurance.

### Regulatory and Compliance Landscape

The organization must support workloads subject to multiple compliance frameworks:

- **SOC 2 Type II** -- Requires audit trail protection, access controls, and encryption.
- **HIPAA** -- Requires that only HIPAA-eligible AWS services be used for regulated data.
- **PCI-DSS** -- Requires network segmentation, encryption, and access logging.
- **NIST 800-53** -- Requires least privilege, continuous monitoring, and data protection.
- **CIS AWS Foundations Benchmark** -- Requires root account lockdown, region restriction, and
  security service protection.

These frameworks overlap significantly. Rather than building one SCP per framework, the design
consolidates overlapping requirements into a minimal set of policies.

### AWS SCP Constraints

AWS imposes hard limits on SCPs that constrain the design:

- **5 SCPs per target.** Each OU or account can have at most 5 customer-managed SCPs attached
  (plus the implicit `FullAWSAccess` default). This is a hard limit that cannot be increased.
- **5,120 bytes per SCP.** Each policy document has a maximum size. Complex policies must be split
  across multiple SCPs.
- **Inheritance.** SCPs attached to a parent OU are inherited by all child OUs and accounts. A deny
  at the root cannot be overridden lower in the hierarchy.
- **No allow-override.** SCPs are deny-only in practice. The effective permissions are the
  intersection of all SCPs in the hierarchy chain from root to account.

### Design Tensions

- **Built-in defaults vs. full customization.** Organizations want opinionated defaults that work
  out of the box, but also need the ability to customize for unique requirements.
- **OU-level vs. account-level attachment.** Attaching at the OU level is cleaner but less granular.
  Attaching at the account level is more flexible but harder to audit and more likely to exhaust the
  5-SCP limit.
- **Exempt roles.** Some operations (break-glass, automated remediation) must bypass SCP
  restrictions. But overly broad exemptions defeat the purpose of SCPs.

## Decision

### 7 Default SCPs + 1 Optional HIPAA SCP

The Organizations module ships with **7 built-in SCPs** that are generated from
`aws_iam_policy_document` data sources, plus **1 optional HIPAA-specific SCP**:

| # | SCP Name | Purpose | Frameworks Addressed |
|---|----------|---------|---------------------|
| 1 | `baseline-guardrails` | Prevent organization departure, root user lockdown, protect OrganizationAccountAccessRole, deny region/password policy changes | SOC 2, NIST 800-53, CIS |
| 2 | `protect-security-services` | Prevent disabling CloudTrail, Config, GuardDuty, Security Hub, Access Analyzer, VPC Flow Logs | SOC 2, NIST 800-53, PCI-DSS, CIS |
| 3 | `enforce-encryption` | Require EBS/RDS encryption, protect KMS keys, enforce IMDSv2 | HIPAA, PCI-DSS, NIST 800-53, CIS |
| 4 | `deny-regions` | Restrict resource creation to allowed regions (us-east-1, us-west-2) with global service exemptions | PCI-DSS, NIST 800-53, data residency |
| 5 | `protect-data-and-network` | Block S3 public access changes, default VPC creation, external RAM sharing, backup deletion; protect `Team`-tag integrity for per-team ABAC (`DenyTeamTagTampering`, #62) | SOC 2, PCI-DSS, NIST 800-53 |
| 6 | `require-tagging` | Dynamic deny for resource creation without required tags (Environment, ManagedBy, Owner) | SOC 2 (asset management), cost allocation |
| 7 | `restrict-iam-users` | Deny IAM user/access key creation and direct user policy attachment (force federation) | SOC 2, NIST 800-53, CIS |
| 8 | `hipaa-eligible-services` | Allowlist of HIPAA BAA-covered services (optional, off by default) | HIPAA |

### Escape Hatch: Full Override via `service_control_policies`

The `service_control_policies` variable accepts a `map(string)` of SCP name to JSON document. When
set to any non-null value, it **completely replaces** all 7 built-in SCPs:

```hcl
variable "service_control_policies" {
  description = "Custom SCP JSON map override. When set, replaces all built-in default SCPs."
  type        = map(string)
  default     = null
}
```

This is an all-or-nothing override, not a merge. The rationale: SCPs interact in complex ways
through their intersection semantics. Merging custom policies with built-in defaults could create
unexpected permission gaps or conflicts that are extremely difficult to debug. A full replacement
forces the operator to reason about the complete SCP set.

The implementation uses a conditional pattern throughout:

```hcl
data "aws_iam_policy_document" "baseline_guardrails" {
  count = local.create && var.service_control_policies == null ? 1 : 0
  # ...
}
```

When `service_control_policies` is non-null, none of the built-in policy documents are generated.

### Exempt Role Pattern

All deny statements include a condition that exempts specific IAM roles:

```hcl
condition {
  test     = "ArnNotLike"
  variable = "aws:PrincipalArn"
  values   = local.exempt_role_arns  # ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
}
```

The module's default exempt role is `OrganizationAccountAccessRole` (the cross-account administrative
role AWS Organizations creates in every member account — used for initial setup and break-glass). The
`exempt_roles` variable adds more; in the live org these include **`PlatformDeployer`** (the Terragrunt
apply role — it *must* be exempt, or every apply would hit SCP denies), the Terratest CI role (see
[ADR-007](007-iam-role-model.md)), and the IaC controllers that must set governance tags on resources
they create — `crossplane-ecr-provisioner`, `crossplane-provisioner-*`, and the per-cluster
`platform-use1-eks-karpenter-*` / `preprod-use1-eks-karpenter-*` node-provisioner roles (anchored
per-cluster, not a leading wildcard, per a security audit).

The exempt role pattern is deliberately narrow:

- Only IAM roles are exemptable (not users or services).
- The wildcard is on the account ID (`*`), not the role name, so the same role name is exempt across
  all accounts.
- The OrganizationAccountAccessRole itself is protected by a dedicated SCP statement
  (`ProtectOrganizationRole`) that prevents modification by non-exempt principals.

### OU-Level Attachment, Not Account-Level

SCPs are attached at the **OU level**, not at individual accounts:

```hcl
variable "scp_attachments" {
  default = {
    "root"      = ["baseline-guardrails", "protect-security-services", "enforce-encryption", "deny-regions"]
    "Platform"  = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
    "Workloads" = ["protect-data-and-network", "require-tagging", "restrict-iam-users"]
  }
}
```

This means:

- **Root-level SCPs** (4 policies) are inherited by every OU and account in the organization.
- **Platform OU** gets 3 additional SCPs (7 total including inherited) — `require-tagging` and
  `restrict-iam-users` were added alongside `protect-data-and-network` (a security-audit change) so the
  most-privileged account isn't left without tag/IAM-user enforcement; it now matches Workloads.
- **Workloads OU** gets 3 additional SCPs (7 total including inherited).

### 5-Per-Target Budget Allocation Strategy

With a hard limit of 5 SCPs per target, the attachment strategy is designed to leave room for
growth:

| Target | Attached | Inherited | Total Effective | Budget Remaining |
|--------|----------|-----------|-----------------|-----------------|
| Root | 4 | 0 | 4 | 1 |
| Platform | 3 | 4 | 7* | 2 (audit-driven — matches Workloads; child accounts have 5 free slots) |
| Workloads | 3 | 4 | 7* | N/A (child OUs bear the attachment) |
| Workloads/Preprod | 0 | 4 | 4 | 1 (plus child-OU-inherited from Workloads) |
| Workloads/Prod | 0 | 4 | 4 | 1 |
| Workloads/Regulated | 0 | 4 | 4 | 1 |

*Note: The 5-SCP limit applies to directly attached policies per target. Inherited SCPs from
parent OUs are effective but do not count toward the child's 5-SCP attachment limit. The Workloads
OU has 3 directly attached SCPs with 2 remaining slots. Its child OUs inherit all parent SCPs
(root + Workloads) and have all 5 of their own slots free for future environment-specific policies.

This design intentionally keeps most OUs well below the 5-policy direct attachment limit to
accommodate future requirements (e.g., attaching the HIPAA SCP to the Regulated OU).

## Consequences

### Positive

- **Compliance coverage out of the box.** The 7 default SCPs address the core requirements of SOC
  2, HIPAA, PCI-DSS, NIST 800-53, and CIS without any customization.
- **Auditable by inspection.** Each SCP is a named `aws_iam_policy_document` data source with clear
  statement SIDs. Auditors can read the Terraform code to understand the control.
- **Growth headroom.** The 5-SCP budget allocation leaves room for future policies at every level
  of the hierarchy. The HIPAA SCP can be selectively attached to the Regulated OU when needed.
- **Escape hatch for advanced users.** The `service_control_policies` override allows organizations
  with unique requirements to replace the defaults entirely without forking the module.
- **Consistent exempt role handling.** The `exempt_roles` variable is applied uniformly across all
  deny statements, preventing inconsistent exemption patterns.

### Negative

- **All-or-nothing override.** The escape hatch replaces all SCPs, not individual ones. An
  organization that wants to modify a single SCP must copy all 7 defaults and make the change.
  This is intentional (to force holistic reasoning) but increases the maintenance burden for
  customized deployments.
- **Global service exemption list.** The `deny-regions` SCP has a hardcoded list of global services
  (IAM, STS, Route 53, CloudFront, etc.) that must be updated when AWS adds new global services.
- **Tag enforcement limitations.** The `require-tagging` SCP only covers a subset of resource types
  (EC2 instances, S3 buckets, RDS instances). Expanding coverage to all taggable resources would
  exceed the SCP size limit.
- **OrganizationAccountAccessRole dependency.** The exempt role pattern assumes this role exists
  and is properly protected. If the role is deleted or renamed in a member account, the exempt
  pattern breaks silently.

### Risks

- **SCP size limit pressure.** As more statements are added (e.g., additional service protections,
  more required tags), individual SCPs may approach the 5,120-byte limit. Mitigation: monitor
  policy sizes in CI; split policies proactively.
- **Overly broad global service exemptions.** The `deny-regions` SCP exempts entire service
  namespaces (e.g., `iam:*`) rather than specific actions. This is necessary for global services
  but means region-deny does not apply to any IAM actions. Mitigation: other SCPs cover IAM-specific
  controls.
- **HIPAA SCP maintenance.** The HIPAA-eligible services list changes as AWS adds new services to
  its BAA. The `hipaa-eligible-services` SCP must be updated periodically. Mitigation: compare
  against the AWS HIPAA eligible services list during quarterly reviews.
