# Runbook: True cloud cost (CUR → Athena)

The authoritative AWS bill via the Cost & Usage Report, queried through Athena and attributed by the `Team`
cost-allocation tag — the Inform foundation of the platform FinOps practice (#668 / ADR-079 D4, ADR-092). This
is **Phase 1** (the AWS data pipeline). Phase 2a wires OpenCost `cloudCost` to consume it; Phase 3 adds
dashboards.

- **Module:** `infra/modules/aws/cost-export`
- **Unit:** `infra/live/aws/mgmt/global/cost-export/` (apply with `AWS_PROFILE=management`, from the main root)
- **Account:** management/payer (851725353202), us-east-1 — CUR is payer-only and us-east-1-only.

## The 24h lag (read this first)

A new CUR's **first delivery lands ~24h after creation**. So immediately after apply:

- the S3 bucket, CUR definition, Glue crawler, Athena workgroup, and cross-account role exist, but
- the Glue **table does not exist yet** and Athena queries return nothing.

The `Team` cost-allocation tag is already active (#673), so the team column populates from the first delivery —
no extra tag-clock wait.

## Verify (the day after apply)

1. Confirm CUR data has landed in S3:

   ```bash
   AWS_PROFILE=management aws s3 ls "s3://$(cd infra/live/aws/mgmt/global/cost-export && terragrunt output -raw bucket_name)/cur/" --recursive | head
   ```

2. Run (or wait for the scheduled) Glue crawler, then confirm the table exists:

   ```bash
   AWS_PROFILE=management aws glue start-crawler --name platform-cost-export-cur
   AWS_PROFILE=management aws glue get-tables --database-name platform_cur --query 'TableList[].Name'
   ```

3. Query the CUR in Athena (console → workgroup `platform-cost-export`), e.g. spend by team for the current month:

   ```sql
   SELECT resource_tags_user_team AS team, round(sum(line_item_unblended_cost), 2) AS usd
   FROM platform_cur.<table_name>
   WHERE billing_period = date_format(current_date, '%Y-%m')
   GROUP BY 1 ORDER BY 2 DESC;
   ```

   (The crawled table name and exact column names depend on the CUR; browse them in the Glue catalog. If the
   crawler split the data into multiple tables, narrow the crawler `s3_target.path` and re-run.)

## Next: Phase 2a (OpenCost)

`observability-opencost` flips `cloudCost.enabled = true` and assumes the `cost_reader` role
(`terragrunt output -raw cost_reader_role_arn`) to read the CUR via Athena, surfacing true cloud cost in the
existing cost dashboards. Tracked separately under #668.

## Cost

CUR delivery is free; S3 is pennies; the daily Glue crawler is ~$0.15/run; Athena is $5/TB scanned (CUR is
small + columnar). Total ≈ $1–5/mo. Cost Anomaly Detection (#1054) guards against an Athena/Glue runaway.
