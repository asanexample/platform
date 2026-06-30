# ---------------------------------------------------------------------------
# Cost & Usage Report → S3 → Glue → Athena (true cloud cost)
# ---------------------------------------------------------------------------
# The authoritative AWS bill (the actual invoice, incl. the non-cluster spend
# OpenCost can't see — NAT, data transfer, EKS control plane, EBS, NLB, TGW,
# S3/ECR, KMS), attributed by the activated `Team` cost-allocation tag. The
# Inform-phase foundation of the platform FinOps practice (ADR-092 / #668,
# ADR-079 D4). Payer/management account only — a member account can't generate
# an org-wide CUR; Glue + Athena co-locate here (us-east-1; CUR is us-east-1).
#
# Consumed cross-account by OpenCost `cloudCost` on the platform hub, which
# assumes the cost_reader role below (Phase 2a). The standalone Athena workgroup
# also serves ad-hoc CUR SQL.

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

locals {
  create = var.create

  # CUR (legacy) writes Parquet under <prefix>/<report>/<report>/ ; that inner
  # path is the Glue crawler target (the dated partitions live beneath it).
  cur_data_prefix = "${var.s3_prefix}/${var.cur_report_name}/${var.cur_report_name}"
}

# ---------------------------------------------------------------------------
# S3 bucket — CUR storage + Athena query results
# ---------------------------------------------------------------------------
resource "aws_s3_bucket" "cur" {
  count = local.create ? 1 : 0

  bucket_prefix = "${var.name}-"
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "cur" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

# SSE-S3 (AES256), NOT SSE-KMS: the CUR service (billingreports.amazonaws.com)
# can't use the AWS-managed KMS key, and AES256 keeps the cross-account reader
# (OpenCost) free of kms:Decrypt. Same choice as the observability metric/log
# stores; CMK is the regulated-tier upgrade (#118).
resource "aws_s3_bucket_server_side_encryption_configuration" "cur" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "cur" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Expire Athena query results (cheap, regenerable) and old CUR object versions;
# the current CUR is OVERWRITE_REPORT so it stays small.
resource "aws_s3_bucket_lifecycle_configuration" "cur" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id

  rule {
    id     = "expire-athena-results"
    status = "Enabled"
    filter {
      prefix = "${var.athena_results_prefix}/"
    }
    expiration {
      days = var.athena_results_retention_days
    }
  }

  rule {
    id     = "expire-noncurrent-cur"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration {
      noncurrent_days = var.cur_noncurrent_retention_days
    }
  }
}

# Legacy-CUR delivery requires this exact bucket policy (GetBucketAcl/Policy +
# PutObject for billingreports.amazonaws.com, source-scoped to this account's CUR
# definitions); CUR creation fails the policy check without it.
resource "aws_s3_bucket_policy" "cur" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.cur[0].id
  policy = data.aws_iam_policy_document.cur_bucket[0].json
}

data "aws_iam_policy_document" "cur_bucket" {
  count = local.create ? 1 : 0

  statement {
    sid    = "AllowCURBucketPolicyCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl", "s3:GetBucketPolicy"]
    resources = [aws_s3_bucket.cur[0].arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }

  statement {
    sid    = "AllowCURWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["billingreports.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.cur[0].arn}/*"]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cur:us-east-1:${data.aws_caller_identity.current.account_id}:definition/*"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# ---------------------------------------------------------------------------
# Cost & Usage Report (legacy CUR, Athena integration)
# ---------------------------------------------------------------------------
# Legacy CUR (not CUR 2.0 / Data Exports) on purpose: OpenCost's cloudCost Athena
# integration expects the documented legacy-CUR schema. Parquet + hourly +
# RESOURCES (resource ids + the activated cost-allocation tags as columns) +
# OVERWRITE_REPORT (required with the ATHENA artifact; keeps storage flat).
resource "aws_cur_report_definition" "this" {
  count = local.create ? 1 : 0

  report_name                = var.cur_report_name
  time_unit                  = "HOURLY"
  format                     = "Parquet"
  compression                = "Parquet"
  additional_schema_elements = ["RESOURCES"]
  s3_bucket                  = aws_s3_bucket.cur[0].id
  s3_prefix                  = var.s3_prefix
  s3_region                  = data.aws_region.current.region
  additional_artifacts       = ["ATHENA"]
  report_versioning          = "OVERWRITE_REPORT"
  refresh_closed_reports     = true

  depends_on = [aws_s3_bucket_policy.cur]
}

# ---------------------------------------------------------------------------
# Glue Data Catalog — database + crawler
# ---------------------------------------------------------------------------
# A daily crawler auto-discovers the ~100-column CUR schema + month partitions
# (hand-defining the table would not survive CUR schema drift).
resource "aws_glue_catalog_database" "cur" {
  count = local.create ? 1 : 0

  name = var.glue_database_name
}

data "aws_iam_policy_document" "glue_crawler_trust" {
  count = local.create ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["glue.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "glue_crawler" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.name}-glue-"
  assume_role_policy = data.aws_iam_policy_document.glue_crawler_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy_attachment" "glue_service" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.glue_crawler[0].id
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSGlueServiceRole"
}

resource "aws_iam_role_policy" "glue_crawler_s3" {
  count = local.create ? 1 : 0

  name = "cur-bucket-read"
  role = aws_iam_role.glue_crawler[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["s3:GetObject", "s3:ListBucket"]
      Resource = [aws_s3_bucket.cur[0].arn, "${aws_s3_bucket.cur[0].arn}/*"]
    }]
  })
}

resource "aws_glue_crawler" "cur" {
  count = local.create ? 1 : 0

  name          = "${var.name}-cur"
  role          = aws_iam_role.glue_crawler[0].arn
  database_name = aws_glue_catalog_database.cur[0].name
  schedule      = var.crawler_schedule

  s3_target {
    path = "s3://${aws_s3_bucket.cur[0].id}/${local.cur_data_prefix}/"
    # Skip CUR metadata/manifests so the crawler infers one clean table.
    exclusions = ["**.json", "**.yml", "**.csv", "**.gz", "**.sql", "**/cost_and_usage_data_status/**"]
  }

  # CUR Parquet schemas drift month to month (columns added); keep the table and
  # only add partitions/columns rather than recreating it.
  schema_change_policy {
    delete_behavior = "LOG"
    update_behavior = "UPDATE_IN_DATABASE"
  }

  configuration = jsonencode({
    Version = 1.0
    Grouping = {
      TableGroupingPolicy = "CombineCompatibleSchemas"
    }
  })

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Athena workgroup
# ---------------------------------------------------------------------------
resource "aws_athena_workgroup" "cur" {
  count = local.create ? 1 : 0

  name = var.name

  configuration {
    enforce_workgroup_configuration    = true
    publish_cloudwatch_metrics_enabled = false

    result_configuration {
      output_location = "s3://${aws_s3_bucket.cur[0].id}/${var.athena_results_prefix}/"
      encryption_configuration {
        encryption_option = "SSE_S3"
      }
    }
  }

  force_destroy = var.force_destroy
  tags          = var.tags
}

# ---------------------------------------------------------------------------
# Cross-account read role (cost_reader)
# ---------------------------------------------------------------------------
# Assumed by the platform-account OpenCost pod-identity role (Phase 2a) to run
# Athena queries against the CUR. Trust is delegated to the platform account
# principals passed in; the actual grant is double-gated by OpenCost's own
# identity policy on the platform side. Created only when a trust list is given.
data "aws_iam_policy_document" "cost_reader_trust" {
  count = local.create && length(var.reader_trusted_principal_arns) > 0 ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "AWS"
      identifiers = var.reader_trusted_principal_arns
    }
  }
}

resource "aws_iam_role" "cost_reader" {
  count = local.create && length(var.reader_trusted_principal_arns) > 0 ? 1 : 0

  name               = var.cost_reader_role_name
  assume_role_policy = data.aws_iam_policy_document.cost_reader_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "cost_reader" {
  count = local.create && length(var.reader_trusted_principal_arns) > 0 ? 1 : 0

  name = "athena-cur-read"
  role = aws_iam_role.cost_reader[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AthenaQuery"
        Effect = "Allow"
        Action = [
          "athena:StartQueryExecution",
          "athena:GetQueryExecution",
          "athena:GetQueryResults",
          "athena:StopQueryExecution",
          "athena:GetWorkGroup",
        ]
        Resource = [aws_athena_workgroup.cur[0].arn]
      },
      {
        Sid    = "GlueCatalogRead"
        Effect = "Allow"
        Action = [
          "glue:GetDatabase",
          "glue:GetDatabases",
          "glue:GetTable",
          "glue:GetTables",
          "glue:GetPartition",
          "glue:GetPartitions",
        ]
        Resource = [
          "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:catalog",
          "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:database/${aws_glue_catalog_database.cur[0].name}",
          "arn:aws:glue:${data.aws_region.current.region}:${data.aws_caller_identity.current.account_id}:table/${aws_glue_catalog_database.cur[0].name}/*",
        ]
      },
      {
        Sid      = "S3ReadCURAndResults"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:ListBucket", "s3:GetBucketLocation", "s3:PutObject"]
        Resource = [aws_s3_bucket.cur[0].arn, "${aws_s3_bucket.cur[0].arn}/*"]
      },
    ]
  })
}
