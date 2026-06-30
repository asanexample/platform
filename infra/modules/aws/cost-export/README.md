# cost-export

The authoritative AWS bill (Cost & Usage Report → S3 → Glue → Athena), attributed by the activated `Team`
cost-allocation tag — the Inform-phase foundation of the platform FinOps practice (ADR-092 / #668, ADR-079 D4,
P11 part 2). Brings the **true invoice** (after discounts, incl. the non-cluster spend OpenCost can't estimate —
NAT, data transfer, EKS control plane, EBS, NLB, TGW, S3/ECR, KMS) into the cost view next to OpenCost's
in-cluster allocation.

**Payer/management account only** (851725353202) — a member account can't generate an org-wide CUR; Glue +
Athena co-locate here (us-east-1, where CUR lives). Deploy from `mgmt/global/`.

## What it creates

- **S3 bucket** — CUR delivery + Athena results. **SSE-S3 (AES256)**, not SSE-KMS: the CUR service
  (`billingreports.amazonaws.com`) can't use the AWS-managed KMS key, and AES256 keeps the cross-account reader
  free of `kms:Decrypt`. CMK is the #118 upgrade.
- **Legacy CUR** (`aws_cur_report_definition`) — Parquet, hourly, `RESOURCES` (resource ids + the activated
  cost-allocation tags as columns), `OVERWRITE_REPORT`, with the `ATHENA` artifact. *Legacy CUR, not CUR 2.0:
  OpenCost's `cloudCost` Athena integration expects the legacy-CUR schema.*
- **Glue** — a catalog database + a daily crawler that auto-discovers the CUR schema/partitions (survives the
  monthly column drift a hand-defined table wouldn't).
- **Athena workgroup** — for OpenCost and ad-hoc CUR SQL; results land in the bucket (lifecycle-expired).
- **Cross-account `cost_reader` role** — assumed by the platform-account OpenCost pod-identity role (Phase 2a)
  to query Athena. Created only when `reader_trusted_principal_arns` is set; double-gated by OpenCost's own
  identity policy on the consumer side.

## Consuming it (Phase 2a, separate)

`observability-opencost` flips `cloudCost.enabled = true` and assumes `cost_reader_role_arn` to read the CUR via
Athena. This module is the producer; it applies and accrues data independently.

## The 24h lag

CUR delivers a few times a day, and the **first delivery lands ~24h after the report is created**. So after
apply, the Glue table won't exist and Athena queries return nothing until the first CUR drop. Verify a day
later (see `docs/runbooks/cost-true-spend.md`). The `Team` cost-allocation tag is already active, so the team
column populates from the first delivery — no extra tag-clock wait.
