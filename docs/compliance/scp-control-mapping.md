# SCP-to-Compliance-Framework Control Mapping

> **Purpose:** Provide auditors and compliance officers with a traceable mapping between
> each Service Control Policy (SCP) statement deployed through the `organizations` module
> and the specific controls they satisfy across six compliance frameworks.
>
> **Module path:** `infra/modules/aws/organizations/scps.tf`
> **Live configuration:** `infra/live/aws/mgmt/global/organizations/terragrunt.hcl`
>
> **Last reviewed:** 2026-06-01

---

## Table of Contents

1. [How to Read This Document](#how-to-read-this-document)
2. [Framework Legend](#framework-legend)
3. [Attachment Summary](#attachment-summary)
4. [SCP 1: baseline-guardrails](#scp-1-baseline-guardrails)
5. [SCP 2: protect-security-services](#scp-2-protect-security-services)
6. [SCP 3: enforce-encryption](#scp-3-enforce-encryption)
7. [SCP 4: deny-regions](#scp-4-deny-regions)
8. [SCP 5: protect-data-and-network](#scp-5-protect-data-and-network)
9. [SCP 6: require-tagging](#scp-6-require-tagging)
10. [SCP 7: restrict-iam-users](#scp-7-restrict-iam-users)
11. [SCP 8: hipaa-eligible-services](#scp-8-hipaa-eligible-services)
12. [Framework Coverage Summary](#framework-coverage-summary)
13. [Evidence Collection Guide](#evidence-collection-guide)

---

## How to Read This Document

Each SCP section contains:

- **Description** -- what the SCP prevents and why it matters.
- **Statement mapping table** -- every SID mapped to one or more controls in each framework.
- **Evidence guidance** -- specific CloudTrail queries, AWS Config rules, and API calls an
  auditor can use to verify the control is active and effective.

The mapping uses the standard identifiers for each framework. Where a control is not
directly applicable, the cell is marked with `--`.

---

## Framework Legend

| Abbreviation | Framework | Version |
|---|---|---|
| **SOC 2** | AICPA Trust Services Criteria | 2017 (CC series) |
| **HIPAA** | Health Insurance Portability and Accountability Act | 45 CFR Parts 160, 164 |
| **PCI-DSS** | Payment Card Industry Data Security Standard | v4.0 |
| **ISO 27001** | Information Security Management System | 2022 (Annex A) |
| **NIST 800-53** | Security and Privacy Controls | Rev. 5 |
| **CIS AWS** | CIS Amazon Web Services Foundations Benchmark | v3.0 |

---

## Attachment Summary

The default `scp_attachments` (from `variables.tf`) control which OUs receive each SCP:

| SCP Name | Attached To |
|---|---|
| baseline-guardrails | Organization Root |
| protect-security-services | Organization Root |
| enforce-encryption | Organization Root |
| deny-regions | Organization Root |
| protect-data-and-network | Platform, Workloads |
| require-tagging | Workloads |
| restrict-iam-users | Workloads |
| hipaa-eligible-services | (Optional, via `enable_hipaa_scp`) |

SCPs attached at the root propagate to every OU and account in the organization. SCPs
attached at a child OU apply only within that subtree.

---

## SCP 1: baseline-guardrails

**Attached to:** Organization Root (all accounts)

### What It Prevents

Prevents member accounts from leaving the organization, blocks all root-user activity
(except `sts:GetSessionToken`), prohibits creation of root access keys, disallows
region enablement/disablement changes, protects the IAM password policy from modification,
and prevents tampering with the `OrganizationAccountAccessRole`.

### Why It Matters

These are foundational identity and account-integrity controls. Without them, a
compromised or rogue account could detach itself from centralized governance, use the
root user to bypass all role-based controls, or weaken password requirements.

### Statement Control Mapping

| Statement SID | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| DenyLeaveOrganization | `organizations:LeaveOrganization` | CC6.1 | 164.312(a)(1) | 7.2.1 | A.5.15 | AC-6, CM-7 | 1.1 |
| DenyRootUserActions | All except `sts:GetSessionToken` (when principal is root) | CC6.1, CC6.3 | 164.312(a)(1), 164.312(d) | 7.2.2, 8.1.1 | A.8.2, A.8.5 | AC-2(1), AC-6(2) | 1.4, 1.7 |
| DenyRootAccessKeys | `iam:CreateAccessKey` (on root) | CC6.1 | 164.312(d) | 8.2.2, 8.6.1 | A.8.5 | AC-6(2), IA-2(1) | 1.4 |
| DenyRegionChanges | `account:EnableRegion`, `account:DisableRegion` | CC6.6 | 164.312(e)(1) | 6.4.1 | A.8.9 | CM-7 | -- |
| DenyPasswordPolicyChanges | `iam:DeleteAccountPasswordPolicy`, `iam:UpdateAccountPasswordPolicy` | CC6.1 | 164.312(a)(1) | 8.3.6 | A.5.17 | IA-5(1) | 1.8, 1.9, 1.10, 1.11 |
| ProtectOrganizationRole | `iam:AttachRolePolicy`, `iam:DeleteRole`, `iam:DeleteRolePolicy`, etc. on `OrganizationAccountAccessRole` | CC6.1, CC6.3 | 164.312(a)(1) | 7.2.1, 7.2.5 | A.8.2 | AC-6, AC-6(5) | -- |

### Evidence Collection

**CloudTrail query -- verify no unauthorized root usage:**

```sql
SELECT eventTime, eventName, sourceIPAddress, errorCode
FROM cloudtrail_logs
WHERE userIdentity.type = 'Root'
  AND eventTime > DATE_ADD('day', -90, NOW())
ORDER BY eventTime DESC;
```

**AWS Config rules:**

- `root-account-mfa-enabled` -- confirms root MFA is active.
- `iam-root-access-key-check` -- confirms root has no active access keys.

**API verification -- SCP is attached:**

```bash
aws organizations list-policies-for-target \
  --target-id <root-id> \
  --filter SERVICE_CONTROL_POLICY \
  | jq '.Policies[] | select(.Name == "baseline-guardrails")'
```

---

## SCP 2: protect-security-services

**Attached to:** Organization Root (all accounts)

### What It Prevents

Prevents disabling or deleting CloudTrail trails, AWS Config recorders and delivery
channels, GuardDuty detectors, Security Hub standards, IAM Access Analyzer, and VPC
Flow Logs. All deny statements are exempted for the `OrganizationAccountAccessRole`.

### Why It Matters

Security monitoring services form the detective layer of defense-in-depth. If an attacker
disables CloudTrail, there is no audit trail. If Config is stopped, drift detection halts.
Disabling GuardDuty or Security Hub removes threat intelligence and compliance dashboards.

### Statement Control Mapping

| Statement SID | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| ProtectCloudTrail | `cloudtrail:StopLogging`, `DeleteTrail`, `UpdateTrail`, `PutEventSelectors` | CC7.2, CC7.3 | 164.312(b) | 10.2.1, 10.3.1 | A.8.15 | AU-2, AU-3, AU-6, AU-12 | 3.1, 3.2, 3.4 |
| ProtectConfig | `config:StopConfigurationRecorder`, `DeleteConfigurationRecorder`, `DeleteDeliveryChannel`, `DeleteRetentionConfiguration` | CC7.1 | 164.312(b) | 10.2.1 | A.8.15 | CM-3, CM-8, AU-6 | 3.5 |
| ProtectGuardDuty | `guardduty:DeleteDetector`, `DisassociateFromMasterAccount`, `StopMonitoringMembers`, `UpdateDetector` | CC7.2, CC7.3 | 164.308(a)(1)(ii)(D) | 11.5.1 | A.8.16 | SI-4, IR-4 | -- |
| ProtectSecurityHub | `securityhub:DisableSecurityHub`, `BatchDisableStandards`, `DeleteMembers`, `DisassociateFromMasterAccount` | CC7.2 | 164.308(a)(1)(ii)(D) | 11.5.1 | A.8.16 | SI-4, CA-7 | -- |
| ProtectAccessAnalyzer | `access-analyzer:DeleteAnalyzer` | CC6.1 | 164.308(a)(4)(ii)(C) | 7.2.5 | A.5.15 | AC-6(3), CA-7 | 1.20 |
| ProtectFlowLogs | `ec2:DeleteFlowLogs` | CC7.2 | 164.312(b) | 10.2.1 | A.8.15, A.8.20 | AU-12, SI-4 | 3.7 |

### Evidence Collection

**CloudTrail query -- verify no tampering attempts:**

```sql
SELECT eventTime, eventName, userIdentity.arn, errorCode, errorMessage
FROM cloudtrail_logs
WHERE eventName IN (
  'StopLogging', 'DeleteTrail', 'StopConfigurationRecorder',
  'DeleteDetector', 'DisableSecurityHub', 'DeleteAnalyzer', 'DeleteFlowLogs'
)
  AND eventTime > DATE_ADD('day', -90, NOW())
ORDER BY eventTime DESC;
```

**AWS Config rules:**

- `cloud-trail-log-file-validation-enabled`
- `cloudtrail-enabled`
- `guardduty-enabled-centralized`
- `securityhub-enabled`
- `vpc-flow-logs-enabled`

**API verification -- services are active:**

```bash
# CloudTrail
aws cloudtrail get-trail-status --name <trail-name> \
  | jq '.IsLogging'

# GuardDuty
aws guardduty list-detectors | jq '.DetectorIds'

# Security Hub
aws securityhub describe-hub | jq '.HubArn'
```

---

## SCP 3: enforce-encryption

**Attached to:** Organization Root (all accounts)

### What It Prevents

Blocks disabling EBS default encryption, creating unencrypted EBS volumes, launching
instances with an unencrypted block device, uploading unencrypted S3 objects, creating
unencrypted RDS instances or clusters, scheduling KMS key deletion or disabling keys,
and launching EC2 instances without IMDSv2 (instance metadata service version 2).

### Why It Matters

Encryption at rest and secure instance metadata access are non-negotiable for every
major compliance framework. Unencrypted storage creates direct exposure risk for
sensitive data. IMDSv1 is vulnerable to SSRF-based credential theft.

### Statement Control Mapping

| Statement SID | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| DenyDisableEbsDefault | `ec2:DisableEbsEncryptionByDefault` | CC6.1, CC6.7 | 164.312(a)(2)(iv) | 3.4.1 | A.8.24 | SC-28, SC-28(1) | 2.2.1 |
| DenyUnencryptedVolumes | `ec2:CreateVolume` (when `ec2:Encrypted=false`) | CC6.1, CC6.7 | 164.312(a)(2)(iv) | 3.4.1 | A.8.24 | SC-28 | 2.2.1 |
| DenyUnencryptedEbsOnLaunch | `ec2:RunInstances` (when a block device is unencrypted) | CC6.1, CC6.7 | 164.312(a)(2)(iv) | 3.4.1 | A.8.24 | SC-28 | 2.2.1 |
| DenyUnencryptedS3Uploads | `s3:PutObject` (when `s3:x-amz-server-side-encryption` is absent) | CC6.1, CC6.7 | 164.312(a)(2)(iv) | 3.4.1 | A.8.24 | SC-28 | 2.1.1 |
| DenyUnencryptedRds | `rds:CreateDBInstance` (when `rds:StorageEncrypted=false`) | CC6.1, CC6.7 | 164.312(a)(2)(iv) | 3.4.1 | A.8.24 | SC-28 | 2.3.1 |
| DenyUnencryptedRdsCluster | `rds:CreateDBCluster` (when `rds:StorageEncrypted=false`) | CC6.1, CC6.7 | 164.312(a)(2)(iv) | 3.4.1 | A.8.24 | SC-28 | 2.3.1 |
| ProtectKmsKeys | `kms:ScheduleKeyDeletion`, `kms:DisableKey` | CC6.1 | 164.312(a)(2)(iv) | 3.5.1, 3.6.1 | A.8.24 | SC-12, SC-12(1) | -- |
| EnforceIMDSv2 | `ec2:RunInstances` (when `ec2:MetadataHttpTokens != required`) | CC6.1, CC6.6 | 164.312(a)(1) | 2.2.1 | A.8.9 | CM-6, SC-28 | 5.6 |

### Evidence Collection

**CloudTrail query -- verify no unencrypted resource creation:**

```sql
SELECT eventTime, eventName, requestParameters, errorCode
FROM cloudtrail_logs
WHERE eventName IN ('CreateVolume', 'CreateDBInstance', 'CreateDBCluster', 'RunInstances')
  AND errorCode = 'AccessDenied'
  AND eventTime > DATE_ADD('day', -90, NOW())
ORDER BY eventTime DESC;
```

**AWS Config rules:**

- `encrypted-volumes`
- `rds-storage-encrypted`
- `ec2-ebs-encryption-by-default`
- `ec2-imdsv2-check`
- `cmk-backing-key-rotation-enabled`

**API verification -- EBS default encryption is on:**

```bash
for region in us-east-1 us-west-2; do
  echo "$region: $(aws ec2 get-ebs-encryption-by-default \
    --region "$region" | jq -r '.EbsEncryptionByDefault')"
done
```

---

## SCP 4: deny-regions

**Attached to:** Organization Root (all accounts)

### What It Prevents

Denies all regional AWS API calls outside of the allowed regions (`us-east-1`,
`us-west-2` by default). Global services such as IAM, STS, Organizations, Route 53,
CloudFront, WAF, Shield, Global Accelerator, Support, Health, Cost Explorer, Billing,
SSO, and others are exempted via `NotAction`.

### Why It Matters

Region restriction is a foundational data residency control. It ensures that compute,
storage, and networking resources cannot be provisioned in regions that fall outside the
organization's compliance boundary, reducing the attack surface and simplifying audit
scope.

### Statement Control Mapping

| Statement SID | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| DenyNonAllowedRegions | All regional actions (via `NotAction` exemptions) when `aws:RequestedRegion` is not in allowed list | CC6.6, CC6.7 | 164.312(e)(1), 164.310(d)(1) | 1.2.5 | A.5.23, A.8.1 | AC-6, CM-7, SC-7 | -- |

**Allowed regions (from `terragrunt.hcl`):** `us-east-1`, `us-west-2`

**Global service exemptions (NotAction list):**

- IAM, STS, Organizations
- Route 53, Route 53 Domains, CloudFront
- WAF, WAFv2, WAF-Regional, Shield
- Global Accelerator, Support, Health
- Cost Explorer, CUR, Budgets, Billing, Account
- Access Analyzer, Trusted Advisor, SSO
- Pricing, Tag, Artifact
- Tax, Free Tier, Invoicing, Payments, Savings Plans

### Evidence Collection

**CloudTrail query -- verify region-denied attempts:**

```sql
SELECT eventTime, eventSource, eventName, awsRegion, errorCode, userIdentity.arn
FROM cloudtrail_logs
WHERE errorCode = 'AccessDenied'
  AND awsRegion NOT IN ('us-east-1', 'us-west-2')
  AND eventTime > DATE_ADD('day', -30, NOW())
ORDER BY eventTime DESC
LIMIT 50;
```

**API verification -- SCP content includes region list:**

```bash
POLICY_ID=$(aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  | jq -r '.Policies[] | select(.Name=="deny-regions") | .Id')
aws organizations describe-policy --policy-id "$POLICY_ID" \
  | jq '.Policy.Content | fromjson'
```

---

## SCP 5: protect-data-and-network

**Attached to:** Platform, Workloads

### What It Prevents

Prevents modification of S3 account-level and bucket-level public access blocks,
blocks creation of default VPCs and default subnets, denies RAM resource shares
with external principals, protects backups (Glacier archives/vaults and AWS Backup
vaults/plans/recovery points) from deletion, and protects the integrity of the `Team`
tag (`DenyTeamTagTampering`) so it can be trusted as the basis for per-team ABAC.

### Why It Matters

Public S3 buckets are the most common cause of cloud data breaches. Default VPCs have
permissive networking that does not meet enterprise security baselines. External RAM
sharing can leak resources to third parties. Backup deletion destroys the last line of
recovery.

### Statement Control Mapping

| Statement SID | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| ProtectS3PublicAccessBlock | `s3:PutAccountPublicAccessBlock`, `s3:PutBucketPublicAccessBlock` | CC6.1, CC6.6 | 164.312(e)(1) | 1.3.1, 1.3.2 | A.8.3, A.8.20 | AC-3, SC-7 | 2.1.4 |
| DenyDefaultVpc | `ec2:CreateDefaultVpc`, `ec2:CreateDefaultSubnet` | CC6.6 | 164.312(e)(1) | 1.2.1 | A.8.20, A.8.22 | SC-7, CM-7 | 5.1 |
| DenyExternalSharing | `ram:CreateResourceShare` (when `ram:AllowsExternalPrincipals=true`) | CC6.1, CC6.6 | 164.308(a)(4)(ii)(B) | 7.2.5 | A.5.19 | AC-3, AC-4 | -- |
| ProtectBackups | `glacier:DeleteArchive`, `DeleteVault`, `backup:DeleteBackupVault`, `DeleteBackupPlan`, `DeleteRecoveryPoint` | CC6.1, CC9.1 | 164.308(a)(7)(ii)(A) | 3.4.1 | A.8.13 | CP-9, CP-10 | -- |
| DenyTeamTagTampering | Tag/untag of the `Team` tag on ECR, IAM roles, Secrets Manager, etc. (except platform/deployer + service-linked roles) | CC6.1, CC6.3 | 164.312(a)(1) | 7.2.1, 7.2.5 | A.5.15, A.8.2 | AC-3, AC-6 | -- |

### Evidence Collection

**AWS Config rules:**

- `s3-account-level-public-access-blocks-periodic`
- `s3-bucket-public-read-prohibited`
- `s3-bucket-public-write-prohibited`
- `vpc-default-security-group-closed`
- `backup-recovery-point-minimum-retention-check`

**API verification -- S3 public access block:**

```bash
aws s3control get-public-access-block --account-id <account-id> \
  | jq '.PublicAccessBlockConfiguration'
```

**CloudTrail query -- verify backup protection:**

```sql
SELECT eventTime, eventName, userIdentity.arn, errorCode
FROM cloudtrail_logs
WHERE eventName IN (
  'DeleteArchive', 'DeleteVault', 'DeleteBackupVault',
  'DeleteBackupPlan', 'DeleteRecoveryPoint'
)
  AND eventTime > DATE_ADD('day', -90, NOW())
ORDER BY eventTime DESC;
```

---

## SCP 6: require-tagging

**Attached to:** Workloads

### What It Prevents

Denies creation of EC2 instances (`ec2:RunInstances`), S3 buckets (`s3:CreateBucket`),
and RDS instances (`rds:CreateDBInstance`) unless the required tags are present. The
required tags are dynamically generated from the `required_tags` variable, which defaults
to: `Environment`, `ManagedBy`, `Owner`.

### Why It Matters

Tags are the primary mechanism for cost allocation, resource ownership, and
environment classification. Without enforced tagging, untagged resources create
blind spots in cost reports, make incident response slower (no owner to contact),
and break automation that relies on tag-based targeting.

### Statement Control Mapping

| Statement SID (per tag) | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| RequireTagEnvironment | `ec2:RunInstances`, `s3:CreateBucket`, `rds:CreateDBInstance` (when tag `Environment` is null) | CC3.1, CC6.1 | 164.310(d)(2)(iii) | 2.2.1 | A.5.9, A.8.9 | CM-8, PM-5 | -- |
| RequireTagManagedBy | Same actions (when tag `ManagedBy` is null) | CC3.1 | 164.310(d)(2)(iii) | 2.2.1 | A.5.9 | CM-8 | -- |
| RequireTagOwner | Same actions (when tag `Owner` is null) | CC3.1 | 164.310(d)(2)(iii) | 12.5.1 | A.5.9 | PM-5 | -- |

### Evidence Collection

**CloudTrail query -- verify tag enforcement denials:**

```sql
SELECT eventTime, eventName, requestParameters, errorCode, errorMessage, userIdentity.arn
FROM cloudtrail_logs
WHERE errorCode = 'AccessDenied'
  AND eventName IN ('RunInstances', 'CreateBucket', 'CreateDBInstance')
  AND errorMessage LIKE '%RequireTag%'
  AND eventTime > DATE_ADD('day', -30, NOW())
ORDER BY eventTime DESC;
```

**AWS Config rules:**

- `required-tags` -- configure with `Environment`, `ManagedBy`, `Owner` keys.

**API verification -- check SCP content for tag requirements:**

```bash
POLICY_ID=$(aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  | jq -r '.Policies[] | select(.Name=="require-tagging") | .Id')
aws organizations describe-policy --policy-id "$POLICY_ID" \
  | jq '.Policy.Content | fromjson | .Statement[].Condition'
```

---

## SCP 7: restrict-iam-users

**Attached to:** Workloads

### What It Prevents

Blocks creation of IAM users (`iam:CreateUser`), console login profiles
(`iam:CreateLoginProfile`), and long-lived access keys (`iam:CreateAccessKey`). Also
prevents attaching IAM policies directly to users (`iam:AttachUserPolicy`,
`iam:PutUserPolicy`).

### Why It Matters

IAM users with long-lived credentials are a significant security risk. Federated access
through SSO (via `sso.amazonaws.com` which is enabled as a service principal) is the
preferred pattern. This SCP forces the use of IAM roles and temporary credentials,
ensuring all human access is brokered through the identity provider.

### Statement Control Mapping

| Statement SID | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| DenyIamUserCreation | `iam:CreateUser`, `iam:CreateLoginProfile`, `iam:CreateAccessKey` | CC6.1, CC6.2 | 164.312(a)(1), 164.312(d) | 7.2.1, 8.2.2, 8.6.1 | A.5.16, A.8.2 | AC-2, IA-2, IA-5 | 1.14, 1.16 |
| DenyUserPolicyAttachment | `iam:AttachUserPolicy`, `iam:PutUserPolicy` | CC6.1, CC6.3 | 164.312(a)(1) | 7.2.1, 7.2.5 | A.5.15, A.8.2 | AC-2(7), AC-6 | 1.15 |

### Evidence Collection

**CloudTrail query -- verify no IAM user creation:**

```sql
SELECT eventTime, eventName, userIdentity.arn, errorCode
FROM cloudtrail_logs
WHERE eventName IN ('CreateUser', 'CreateLoginProfile', 'CreateAccessKey',
                    'AttachUserPolicy', 'PutUserPolicy')
  AND eventTime > DATE_ADD('day', -90, NOW())
ORDER BY eventTime DESC;
```

**AWS Config rules:**

- `iam-user-no-policies-check`
- `iam-no-inline-policy-check`

**API verification -- list existing IAM users (should be empty in Workloads):**

```bash
aws iam list-users --query 'Users[].UserName'
```

---

## SCP 8: hipaa-eligible-services

**Attached to:** Optional (enable via `enable_hipaa_scp = true`)

### What It Prevents

Denies all API calls to AWS services that are NOT on the AWS HIPAA Eligible Services
list. This is an allowlist approach -- the `NotAction` block enumerates every HIPAA-eligible
service, and anything not in that list is denied.

### Why It Matters

Under the HIPAA Security Rule, covered entities and business associates must ensure
that electronic Protected Health Information (ePHI) is only processed by services
covered under a Business Associate Agreement (BAA). AWS only signs BAAs for services
on the HIPAA Eligible Services list. Using a non-eligible service for ePHI workloads
is a compliance violation.

### Statement Control Mapping

| Statement SID | Denied Actions | SOC 2 | HIPAA | PCI-DSS | ISO 27001 | NIST 800-53 | CIS AWS |
|---|---|---|---|---|---|---|---|
| DenyNonHipaaServices | All actions NOT in the HIPAA-eligible allowlist (~117 services) | CC6.1 | 164.308(a)(1)(ii)(B), 164.308(a)(4)(ii)(B), 164.312(a)(1) | -- | A.5.23 | SA-9, CM-7, AC-6 | -- |

**HIPAA-eligible services included in the allowlist (partial list):**

- Compute: EC2, ECS, EKS, Lambda, Batch, Elastic Beanstalk
- Storage: S3, EBS, EFS, FSx, Glacier, Storage Gateway, Backup
- Database: RDS, DynamoDB, ElastiCache, Neptune, QLDB, Redshift, Timestream
- Networking: VPC (via EC2), Direct Connect, Route 53, Global Accelerator, App Mesh
- Security: IAM, KMS, CloudHSM, GuardDuty, Macie, Security Hub, Inspector, Shield, WAF
- Management: CloudTrail, CloudWatch, Config, Organizations, SSO, SSM, CloudFormation
- Analytics: Athena, EMR, Kinesis, Glue, QuickSight, Managed Streaming for Kafka
- ML/AI: SageMaker, Comprehend, Comprehend Medical, Rekognition, Textract, Transcribe, Translate, Polly, Lex, HealthLake
- Application: API Gateway, AppSync, SQS, SNS, SES, Step Functions, SWF, EventBridge

### Evidence Collection

**API verification -- confirm HIPAA SCP is active (when enabled):**

```bash
aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
  | jq '.Policies[] | select(.Name == "hipaa-eligible-services")'
```

**CloudTrail query -- detect denied non-HIPAA service usage:**

```sql
SELECT eventTime, eventSource, eventName, userIdentity.arn, errorCode
FROM cloudtrail_logs
WHERE errorCode = 'AccessDenied'
  AND errorMessage LIKE '%DenyNonHipaaServices%'
  AND eventTime > DATE_ADD('day', -30, NOW())
ORDER BY eventTime DESC;
```

---

## Framework Coverage Summary

### SOC 2 Trust Services Criteria

| Criteria | Description | Covered By SCPs | Coverage Level |
|---|---|---|---|
| CC3.1 | Risk Assessment | require-tagging | Partial -- asset inventory support |
| CC6.1 | Logical Access Controls | baseline-guardrails, protect-security-services, enforce-encryption, protect-data-and-network, restrict-iam-users | Full |
| CC6.2 | Credential Management | restrict-iam-users | Full |
| CC6.3 | Least Privilege | baseline-guardrails, restrict-iam-users | Full |
| CC6.6 | Boundary Protection | deny-regions, protect-data-and-network, enforce-encryption | Full |
| CC6.7 | Data Confidentiality | enforce-encryption, deny-regions | Full |
| CC7.1 | Configuration Monitoring | protect-security-services | Full |
| CC7.2 | Security Monitoring | protect-security-services | Full |
| CC7.3 | Incident Detection | protect-security-services | Full |
| CC9.1 | Business Continuity | protect-data-and-network | Partial -- backup protection only |

**Overall SOC 2 coverage: Full for core CC6/CC7 criteria.**

### HIPAA Security Rule

| Section | Description | Covered By SCPs | Coverage Level |
|---|---|---|---|
| 164.308(a)(1)(ii)(B) | Risk Management | hipaa-eligible-services | Full (when enabled) |
| 164.308(a)(1)(ii)(D) | Information System Activity Review | protect-security-services | Full |
| 164.308(a)(4)(ii)(B) | Access Authorization | hipaa-eligible-services, protect-data-and-network | Full |
| 164.308(a)(4)(ii)(C) | Access Establishment | protect-security-services | Partial |
| 164.308(a)(7)(ii)(A) | Data Backup Plan | protect-data-and-network | Full |
| 164.310(d)(1) | Device and Media Controls | deny-regions | Partial |
| 164.310(d)(2)(iii) | Accountability | require-tagging | Full |
| 164.312(a)(1) | Access Control | baseline-guardrails, enforce-encryption, restrict-iam-users, hipaa-eligible-services | Full |
| 164.312(a)(2)(iv) | Encryption and Decryption | enforce-encryption | Full |
| 164.312(b) | Audit Controls | protect-security-services | Full |
| 164.312(d) | Authentication | baseline-guardrails, restrict-iam-users | Full |
| 164.312(e)(1) | Transmission Security | deny-regions, protect-data-and-network | Partial |

**Overall HIPAA coverage: Full when `enable_hipaa_scp = true`. Partial without it.**

### PCI-DSS v4.0

| Requirement | Description | Covered By SCPs | Coverage Level |
|---|---|---|---|
| 1.2.1 | Network Security Controls | protect-data-and-network | Full |
| 1.2.5 | Restrict Traffic | deny-regions | Full |
| 1.3.1, 1.3.2 | Access to CDE | protect-data-and-network | Full |
| 2.2.1 | System Configuration Standards | enforce-encryption, require-tagging | Full |
| 3.4.1 | Protect Stored Data | enforce-encryption, protect-data-and-network | Full |
| 3.5.1, 3.6.1 | Cryptographic Key Management | enforce-encryption | Full |
| 6.4.1 | Secure Development | baseline-guardrails | Partial |
| 7.2.1 | Access Control System | baseline-guardrails, restrict-iam-users | Full |
| 7.2.2 | Restrict Privileged Access | baseline-guardrails | Full |
| 7.2.5 | Periodic Access Review | protect-security-services, protect-data-and-network, restrict-iam-users | Full |
| 8.1.1 | Unique ID Assignment | baseline-guardrails | Full |
| 8.2.2, 8.6.1 | Strong Authentication | baseline-guardrails, restrict-iam-users | Full |
| 8.3.6 | Password Policy | baseline-guardrails | Full |
| 10.2.1 | Audit Trail | protect-security-services | Full |
| 10.3.1 | Audit Trail Protection | protect-security-services | Full |
| 11.5.1 | Intrusion Detection | protect-security-services | Full |
| 12.5.1 | Information Security Responsibility | require-tagging | Partial |

**Overall PCI-DSS coverage: Full for core requirements 1, 2, 3, 7, 8, 10, 11.**

### ISO 27001:2022 Annex A

| Control | Description | Covered By SCPs | Coverage Level |
|---|---|---|---|
| A.5.9 | Inventory of Assets | require-tagging | Full |
| A.5.15 | Access Control | baseline-guardrails, protect-security-services, restrict-iam-users | Full |
| A.5.16 | Identity Management | restrict-iam-users | Full |
| A.5.17 | Authentication Information | baseline-guardrails | Full |
| A.5.19 | Supplier Relationships | protect-data-and-network | Partial |
| A.5.23 | Cloud Service Usage | deny-regions, hipaa-eligible-services | Full |
| A.8.1 | Asset Management | deny-regions | Full |
| A.8.2 | Privileged Access | baseline-guardrails, restrict-iam-users | Full |
| A.8.3 | Information Access Restriction | protect-data-and-network | Full |
| A.8.5 | Secure Authentication | baseline-guardrails | Full |
| A.8.9 | Configuration Management | baseline-guardrails, enforce-encryption, require-tagging | Full |
| A.8.13 | Backup | protect-data-and-network | Full |
| A.8.15 | Logging | protect-security-services | Full |
| A.8.16 | Monitoring | protect-security-services | Full |
| A.8.20 | Network Security | protect-security-services, protect-data-and-network | Full |
| A.8.22 | Segregation of Networks | protect-data-and-network | Full |
| A.8.24 | Cryptography | enforce-encryption | Full |

**Overall ISO 27001 coverage: Full for Annex A controls addressed by preventive SCPs.**

### NIST 800-53 Rev. 5

| Control Family | Controls Addressed | Covered By SCPs |
|---|---|---|
| AC (Access Control) | AC-2, AC-2(1), AC-2(7), AC-3, AC-4, AC-6, AC-6(2), AC-6(3), AC-6(5) | baseline-guardrails, protect-data-and-network, restrict-iam-users |
| AU (Audit) | AU-2, AU-3, AU-6, AU-12 | protect-security-services |
| CA (Assessment) | CA-7 | protect-security-services |
| CM (Configuration) | CM-3, CM-6, CM-7, CM-8 | baseline-guardrails, protect-security-services, enforce-encryption, deny-regions, require-tagging |
| CP (Contingency) | CP-9, CP-10 | protect-data-and-network |
| IA (Identification) | IA-2, IA-2(1), IA-5, IA-5(1) | baseline-guardrails, restrict-iam-users |
| PM (Program Mgmt) | PM-5 | require-tagging |
| SA (Acquisition) | SA-9 | hipaa-eligible-services |
| SC (System/Comms) | SC-7, SC-12, SC-12(1), SC-28, SC-28(1) | enforce-encryption, deny-regions, protect-data-and-network |
| SI (System Integrity) | SI-4 | protect-security-services |
| IR (Incident Response) | IR-4 | protect-security-services |

**Overall NIST 800-53 coverage: 11 control families addressed. Full coverage for AC, AU, CM, SC families.**

### CIS AWS Foundations Benchmark v3.0

| Benchmark # | Description | Covered By SCPs | Coverage Level |
|---|---|---|---|
| 1.1 | Maintain current contact details | baseline-guardrails (prevents org departure) | Partial |
| 1.4 | Ensure no root access keys | baseline-guardrails | Full |
| 1.7 | Eliminate root usage | baseline-guardrails | Full |
| 1.8-1.11 | Password policy | baseline-guardrails | Full |
| 1.14 | No access keys during initial user setup | restrict-iam-users | Full |
| 1.15 | No inline/attached policies on users | restrict-iam-users | Full |
| 1.16 | No IAM user credentials unused | restrict-iam-users (prevents creation) | Full |
| 1.20 | Support IAM Access Analyzer | protect-security-services | Full |
| 2.1.4 | S3 public access blocked | protect-data-and-network | Full |
| 2.2.1 | EBS encryption by default | enforce-encryption | Full |
| 2.3.1 | RDS encryption enabled | enforce-encryption | Full |
| 3.1-3.4 | CloudTrail enabled and protected | protect-security-services | Full |
| 3.5 | AWS Config enabled | protect-security-services | Full |
| 3.7 | VPC Flow Logs enabled | protect-security-services | Full |
| 5.1 | No default VPCs | protect-data-and-network | Full |
| 5.6 | IMDSv2 required | enforce-encryption | Full |

**Overall CIS coverage: Full for benchmarks addressable by preventive SCPs.**

---

## Evidence Collection Guide

### For Annual Audits (SOC 2, ISO 27001)

1. **Export SCP list and contents:**

   ```bash
   for policy in $(aws organizations list-policies --filter SERVICE_CONTROL_POLICY \
     --query 'Policies[].Id' --output text); do
     aws organizations describe-policy --policy-id "$policy" \
       --query 'Policy.{Name:PolicySummary.Name,Content:Content}' > "scp-${policy}.json"
   done
   ```

2. **Export SCP attachment map:**

   ```bash
   for target_id in $(aws organizations list-roots --query 'Roots[].Id' --output text) \
     $(aws organizations list-organizational-units-for-parent --parent-id <root-id> \
       --query 'OrganizationalUnits[].Id' --output text); do
     echo "=== $target_id ==="
     aws organizations list-policies-for-target \
       --target-id "$target_id" --filter SERVICE_CONTROL_POLICY
   done
   ```

3. **Export CloudTrail events showing SCP denials (last 90 days):**

   ```bash
   aws cloudtrail lookup-events \
     --lookup-attributes AttributeKey=EventName,AttributeValue=AccessDenied \
     --start-time "$(date -d '-90 days' +%Y-%m-%dT%H:%M:%SZ)" \
     --max-items 1000 > cloudtrail-denials-90d.json
   ```

4. **Export Terraform state for organizations module:**

   ```bash
   cd infra/live/aws/mgmt/global/organizations
   terragrunt state list
   terragrunt state show aws_organizations_policy.this[\"baseline-guardrails\"]
   ```

### For Continuous Monitoring

- **AWS Config Conformance Packs:** Deploy conformance packs for SOC 2, HIPAA, PCI-DSS,
  and CIS benchmarks. These continuously evaluate AWS Config rules and produce compliance
  scores.

- **Security Hub Standards:** Enable the following Security Hub standards:
  - AWS Foundational Security Best Practices
  - CIS AWS Foundations Benchmark
  - PCI DSS
  These standards automatically evaluate relevant controls and surface findings.

- **CloudWatch Alarms:** Set alarms on CloudTrail for `AccessDenied` events from SCP
  enforcement. High volumes may indicate misconfigured applications or attack attempts.

### Exempt Role Governance

Most SCP deny statements include an `ArnNotLike` condition for exempt roles. The live
configuration sets **three** exempt roles (`var.exempt_roles` in the mgmt org unit):

- `OrganizationAccountAccessRole` — AWS-created in each member account for management-account
  (break-glass) access.
- `PlatformDeployer` — the Terragrunt/IaC apply role; must perform the administrative operations
  the Deny statements otherwise block (manage encryption defaults, tag resources, etc.).
- `github-actions-terratest` — the CI integration-test role in the Test sandbox account.

Note a subset of statements (`DenyLeaveOrganization`, `DenyRootUserActions`, `DenyRootAccessKeys`,
the unencrypted-resource denies, `EnforceIMDSv2`) have **no exemption** and bind even these roles.

**Auditor note:** Verify that the exempt role list (`var.exempt_roles`) has not been
expanded beyond these three / operational necessity. Check the Terraform variable definition and the
live Terragrunt inputs:

```bash
# Check default in module
grep -A5 'variable "exempt_roles"' infra/modules/aws/organizations/variables.tf

# Check live override (if any)
grep -A5 'exempt_roles' infra/live/aws/mgmt/global/organizations/terragrunt.hcl
```

If `exempt_roles` has been expanded, request justification and approval documentation
from the infrastructure team.
