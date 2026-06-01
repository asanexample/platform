# ADR-037: CloudTrail for Secrets Audit Logging

**Date:** 2026-05-28

**Status:** Accepted

## Context

The platform stores sensitive credentials in AWS Secrets Manager across multiple accounts
(ADR-024, ADR-026). Compliance frameworks (SOC 2, HIPAA) mandate audit trails for sensitive
operations: who accessed a secret, when, and from where. Without audit logging, there is no
way to detect unauthorized secret access, investigate credential leaks, or demonstrate
compliance during audits.

AWS CloudTrail records API-level activity for all AWS services, including Secrets Manager
operations like `GetSecretValue`, `PutSecretValue`, `CreateSecret`, and `DeleteSecret`. By
enabling CloudTrail with CloudWatch integration, the platform can create metric filters and
alarms that trigger on secrets-related activity, providing near-real-time visibility into
sensitive operations.

The platform and preprod accounts both run EKS clusters with ESO deployments that read
secrets via IRSA (ADR-018, ADR-019). These automated reads are expected and frequent, but
human reads via the console or CLI, secret mutations (creates, updates, deletes), and reads
from unexpected principals are all events that should be captured and, in some cases, alerted
on.

### Alternatives Considered

**1. Per-account CloudTrail with S3 storage and CloudWatch alarms (chosen).** Each account
gets its own CloudTrail trail writing to a local S3 bucket with versioning, lifecycle
expiration, and public access blocking. CloudWatch Logs integration enables metric filters
and alarms for secrets-related API calls. This provides per-account isolation that mirrors
the secrets architecture (ADR-024) — audit logs for preprod secrets stay in the preprod
account, and platform audit logs stay in the platform account. Simple to deploy and reason
about.

**2. Organization trail in the management account.** AWS Organizations supports a single
organization-level trail that captures API activity from all member accounts into a
centralized S3 bucket in the management account. This provides a unified view of all API
calls across the organization. However, it requires cross-account S3 write permissions,
concentrates audit data in a single bucket (increasing blast radius of a bucket compromise),
and mixes audit events from all accounts — making per-account analysis harder. It also adds
resources to the management account, which should remain governance-only with minimal
workloads. A centralized trail can be added later as an aggregation layer without removing
per-account trails.

**3. Third-party SIEM integration (Datadog, Splunk, CloudWatch Logs Insights).** Forward
CloudTrail events to a dedicated SIEM or log analytics platform for richer querying,
correlation, and alerting. Provides better search and dashboarding than native CloudWatch
metric filters. However, it adds cost (SIEM licensing or data ingestion fees), a new
operational dependency, and configuration complexity. The current scale (two accounts, small
team) does not justify the overhead. CloudTrail with CloudWatch metric filters covers the
immediate compliance requirement. A SIEM can be layered on top later by subscribing to the
CloudTrail S3 buckets or CloudWatch log groups.

## Decision

Deploy a per-account CloudTrail trail in each account that runs workloads with secrets
access (platform and preprod). The trail is implemented as a reusable module
(`infra/modules/aws/cloudtrail/`) deployed via Terragrunt units in each account.

### Module Design

The `cloudtrail` module creates the following resources:

1. **S3 bucket** with a `bucket_prefix` derived from the trail name. The bucket has:
   - Versioning enabled — prevents log tampering by preserving all object versions
   - Server-side encryption with `aws:kms` and bucket key enabled — encrypts logs at rest
     using the S3 bucket's default KMS key
   - Public access block — all four block settings enabled (`block_public_acls`,
     `block_public_policy`, `ignore_public_acls`, `restrict_public_buckets`)
   - Lifecycle policy — logs expire after `log_retention_days` (default 90 days)
   - Bucket policy — scoped to the CloudTrail service principal with `aws:SourceArn`
     conditions, allowing only `GetBucketAcl` and `PutObject` from the specific trail ARN

2. **CloudTrail trail** with:
   - Log file validation enabled — cryptographic digest files detect post-delivery log
     tampering
   - Single-region by default (`is_multi_region = false`) — can be extended to multi-region
     when needed
   - Advanced event selectors for data events — configurable via `data_event_selectors` to
     capture true data-plane operations on data-event-eligible services (e.g., S3 object-level
     `GetObject`/`PutObject`, Lambda `Invoke`). Note: Secrets Manager is **not** a data-event
     service — its API calls (including `GetSecretValue`) are management events (see below)

3. **CloudWatch Logs integration** (enabled by default):
   - A CloudWatch log group (`/aws/cloudtrail/<trail-name>`) with configurable retention
     (default 30 days)
   - An IAM role allowing CloudTrail to write to the log group
   - CloudWatch provides the foundation for metric filters and alarms

4. **Secrets Manager alarms** (opt-in via `enable_secrets_alarms`):
   - A metric filter matching `GetSecretValue`, `PutSecretValue`, `CreateSecret`, and
     `DeleteSecret` events
   - A CloudWatch alarm (`<trail-name>-secrets-write-activity`) that fires when any
     secrets write operation occurs within a 5-minute window
   - Missing data is treated as `notBreaching` to avoid false alarms during quiet periods

### Live Unit Configuration

Both the platform and preprod accounts deploy the module with identical configuration:

```hcl
trail_name            = "${env}-${region_abbv}-secrets-audit"
enable_cloudwatch     = true
enable_secrets_alarms = true
log_retention_days    = 90
data_event_selectors  = []
```

Trail naming follows the pattern `<env>-<region>-secrets-audit` (e.g.,
`platform-use1-secrets-audit`, `preprod-use1-secrets-audit`). `data_event_selectors` is empty, so
the trail captures **all management events** (the CloudTrail default when no selector is set —
read + write). Crucially, **Secrets Manager logs `GetSecretValue` and all its other API calls as
management events**, so secret reads and writes are already captured by this trail without any data
event selectors. `data_event_selectors` exists for genuinely data-plane services (S3 objects,
Lambda invokes) and is unused today.

### Deployment Independence

CloudTrail has no dependencies on EKS, networking, or any other infrastructure unit. It can
be deployed or destroyed independently at any point in the stack lifecycle, which is why it
appears at the bottom of the dependency graph with "no deps" in both the platform and preprod
deployment orderings.

## Consequences

### Positive

- Compliance-ready audit trail for secrets operations — every `GetSecretValue`,
  `PutSecretValue`, `CreateSecret`, and `DeleteSecret` call is logged with principal ARN,
  source IP, timestamp, and request parameters
- Per-account isolation mirrors the secrets architecture (ADR-024) — audit logs for each
  account stay in that account's S3 bucket, preventing cross-account log mixing
- Log file validation detects tampering — CloudTrail generates SHA-256 digest files that can
  be independently verified
- S3 versioning, KMS encryption, and public access blocking provide defense-in-depth for
  stored audit logs
- Near-real-time alerting on secrets mutations via CloudWatch metric filters and alarms
- No infrastructure dependencies — can be deployed to a new account before any other unit

### Negative

- Per-account cost — each trail incurs S3 storage costs and CloudWatch Logs ingestion costs.
  Management events are free for the first trail per account; additional trails and data events
  have per-event charges
- No centralized view — investigating cross-account activity (e.g., comparing platform and
  preprod access patterns) requires querying two separate S3 buckets or CloudWatch log groups.
  This can be addressed later with an organization trail or SIEM aggregation
- CloudWatch metric alarms have no SNS topic configured — the alarm changes state but does not
  send notifications. An SNS topic with email or Slack integration should be added when the
  team is ready to act on alerts

### Risks

- S3 lifecycle expiration deletes logs after 90 days. If a compliance investigation requires
  older logs, they will be unavailable. Mitigated by adjusting `log_retention_days` per account
  based on compliance tier (ADR-013) — Prod should use a longer retention when deployed
- The `force_destroy` variable defaults to `false`, which prevents accidental bucket deletion
  via `terraform destroy` if the bucket contains objects. However, the live units do not
  explicitly set this, relying on the default. If `force_destroy` were set to `true` in a live
  unit, a `terraform destroy` would delete all audit logs without confirmation
- Common misconception: `GetSecretValue` is **not** a CloudTrail *data* event. Secrets Manager
  records all its operations (reads and writes) as **management events**, which this trail captures
  by default — so the `secrets-write-activity` metric filter (which matches `GetSecretValue`,
  `PutSecretValue`, `CreateSecret`, `DeleteSecret`) works as intended with `data_event_selectors`
  empty. No data event selectors are needed for secrets audit coverage; they would only matter for
  S3/Lambda-style data-plane logging
