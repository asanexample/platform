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

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.6.0 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | ~> 6.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | ~> 6.0 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_athena_workgroup.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/athena_workgroup) | resource |
| [aws_cur_report_definition.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cur_report_definition) | resource |
| [aws_glue_catalog_database.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_catalog_database) | resource |
| [aws_glue_crawler.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/glue_crawler) | resource |
| [aws_iam_role.cost_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.glue_crawler](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.cost_reader](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.glue_crawler_s3](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.glue_service](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_s3_bucket.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket) | resource |
| [aws_s3_bucket_lifecycle_configuration.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_lifecycle_configuration) | resource |
| [aws_s3_bucket_policy.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_policy) | resource |
| [aws_s3_bucket_public_access_block.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_public_access_block) | resource |
| [aws_s3_bucket_server_side_encryption_configuration.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_server_side_encryption_configuration) | resource |
| [aws_s3_bucket_versioning.cur](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/s3_bucket_versioning) | resource |
| [aws_caller_identity.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/caller_identity) | data source |
| [aws_iam_policy_document.cost_reader_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.cur_bucket](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_iam_policy_document.glue_crawler_trust](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/iam_policy_document) | data source |
| [aws_region.current](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/data-sources/region) | data source |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_athena_results_prefix"></a> [athena\_results\_prefix](#input\_athena\_results\_prefix) | S3 key prefix for Athena query results (lifecycle-expired). | `string` | `"athena-results"` | no |
| <a name="input_athena_results_retention_days"></a> [athena\_results\_retention\_days](#input\_athena\_results\_retention\_days) | Days to retain Athena query results before expiry. | `number` | `14` | no |
| <a name="input_cost_reader_role_name"></a> [cost\_reader\_role\_name](#input\_cost\_reader\_role\_name) | Name of the cross-account read role OpenCost assumes. | `string` | `"platform-cost-reader"` | no |
| <a name="input_crawler_schedule"></a> [crawler\_schedule](#input\_crawler\_schedule) | Cron schedule for the Glue crawler (UTC). Daily by default — CUR refreshes a few times a day, daily catches new partitions cheaply. | `string` | `"cron(0 3 * * ? *)"` | no |
| <a name="input_create"></a> [create](#input\_create) | Whether to create the cost-export resources. | `bool` | `true` | no |
| <a name="input_cur_noncurrent_retention_days"></a> [cur\_noncurrent\_retention\_days](#input\_cur\_noncurrent\_retention\_days) | Days to retain noncurrent CUR object versions (the report is OVERWRITE, so old versions are churn). | `number` | `30` | no |
| <a name="input_cur_report_name"></a> [cur\_report\_name](#input\_cur\_report\_name) | Name of the legacy Cost & Usage Report. | `string` | `"platform-cur"` | no |
| <a name="input_force_destroy"></a> [force\_destroy](#input\_force\_destroy) | Allow destroying the S3 bucket / Athena workgroup with contents (true only for throwaway/test). | `bool` | `false` | no |
| <a name="input_glue_database_name"></a> [glue\_database\_name](#input\_glue\_database\_name) | Glue Data Catalog database the CUR table is crawled into. | `string` | `"platform_cur"` | no |
| <a name="input_name"></a> [name](#input\_name) | Base name/prefix for resources (S3 bucket prefix, Glue crawler, Athena workgroup, IAM roles). | `string` | `"platform-cost-export"` | no |
| <a name="input_reader_trusted_principal_arns"></a> [reader\_trusted\_principal\_arns](#input\_reader\_trusted\_principal\_arns) | Principal ARNs (in the consumer account, e.g. the platform OpenCost pod-identity role or that account's root) allowed to assume the cross-account cost\_reader role. Empty disables the role (the AWS infra still applies). | `list(string)` | `[]` | no |
| <a name="input_s3_prefix"></a> [s3\_prefix](#input\_s3\_prefix) | S3 key prefix under which the CUR is delivered. | `string` | `"cur"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags applied to taggable resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_athena_results_location"></a> [athena\_results\_location](#output\_athena\_results\_location) | s3:// URI Athena writes query RESULTS to (the workgroup's configured output\_location) — NOT the CUR data location, which is implicit in the Glue table. |
| <a name="output_athena_workgroup_name"></a> [athena\_workgroup\_name](#output\_athena\_workgroup\_name) | Athena workgroup for CUR queries. |
| <a name="output_bucket_name"></a> [bucket\_name](#output\_bucket\_name) | Name of the CUR / Athena-results S3 bucket. |
| <a name="output_cost_reader_role_arn"></a> [cost\_reader\_role\_arn](#output\_cost\_reader\_role\_arn) | ARN of the cross-account read role OpenCost assumes (null when no trust principals are given). |
| <a name="output_cur_report_name"></a> [cur\_report\_name](#output\_cur\_report\_name) | Name of the Cost & Usage Report. |
| <a name="output_glue_database_name"></a> [glue\_database\_name](#output\_glue\_database\_name) | Glue database holding the crawled CUR table. |
<!-- END_TF_DOCS -->