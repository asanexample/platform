locals {
  create = var.create
}

data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# ---------------------------------------------------------------------------
# S3 Bucket for CloudTrail Logs
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "trail" {
  count = local.create ? 1 : 0

  bucket_prefix = "${var.trail_name}-"
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_versioning" "trail" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "trail" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "aws:kms"
    }
    bucket_key_enabled = true
  }
}

resource "aws_s3_bucket_public_access_block" "trail" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_lifecycle_configuration" "trail" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id

  rule {
    id     = "expire-logs"
    status = "Enabled"

    expiration {
      days = var.log_retention_days
    }
  }
}

resource "aws_s3_bucket_policy" "trail" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.trail[0].id
  policy = data.aws_iam_policy_document.trail_bucket[0].json
}

data "aws_iam_policy_document" "trail_bucket" {
  count = local.create ? 1 : 0

  statement {
    sid    = "AWSCloudTrailAclCheck"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:GetBucketAcl"]
    resources = [aws_s3_bucket.trail[0].arn]
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:trail/${var.trail_name}"]
    }
  }

  statement {
    sid    = "AWSCloudTrailWrite"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["cloudtrail.amazonaws.com"]
    }
    actions   = ["s3:PutObject"]
    resources = ["${aws_s3_bucket.trail[0].arn}/AWSLogs/${data.aws_caller_identity.current.account_id}/*"]
    condition {
      test     = "StringEquals"
      variable = "s3:x-amz-acl"
      values   = ["bucket-owner-full-control"]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceArn"
      values   = ["arn:aws:cloudtrail:${data.aws_region.current.id}:${data.aws_caller_identity.current.account_id}:trail/${var.trail_name}"]
    }
  }
}

# ---------------------------------------------------------------------------
# CloudWatch Log Group (for metric filters + alarms)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "trail" {
  count = local.create && var.enable_cloudwatch ? 1 : 0

  name              = "/aws/cloudtrail/${var.trail_name}"
  retention_in_days = var.cloudwatch_retention_days

  tags = var.tags
}

resource "aws_iam_role" "cloudtrail_cloudwatch" {
  count = local.create && var.enable_cloudwatch ? 1 : 0

  name_prefix = "${var.trail_name}-cw-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "cloudtrail.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "cloudtrail_cloudwatch" {
  count = local.create && var.enable_cloudwatch ? 1 : 0

  name_prefix = "cloudwatch-"
  role        = aws_iam_role.cloudtrail_cloudwatch[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "logs:CreateLogStream",
        "logs:PutLogEvents",
      ]
      Resource = "${aws_cloudwatch_log_group.trail[0].arn}:*"
    }]
  })
}

# ---------------------------------------------------------------------------
# CloudTrail
# ---------------------------------------------------------------------------

resource "aws_cloudtrail" "this" {
  count = local.create ? 1 : 0

  name                       = var.trail_name
  s3_bucket_name             = aws_s3_bucket.trail[0].id
  is_multi_region_trail      = var.is_multi_region
  enable_log_file_validation = true

  cloud_watch_logs_group_arn = var.enable_cloudwatch ? "${aws_cloudwatch_log_group.trail[0].arn}:*" : null
  cloud_watch_logs_role_arn  = var.enable_cloudwatch ? aws_iam_role.cloudtrail_cloudwatch[0].arn : null

  dynamic "advanced_event_selector" {
    for_each = var.data_event_selectors
    content {
      name = advanced_event_selector.value.name

      field_selector {
        field  = "eventCategory"
        equals = ["Data"]
      }

      field_selector {
        field  = "resources.type"
        equals = [advanced_event_selector.value.resource_type]
      }

      dynamic "field_selector" {
        for_each = length(advanced_event_selector.value.resource_arns) > 0 ? [1] : []
        content {
          field       = "resources.ARN"
          starts_with = advanced_event_selector.value.resource_arns
        }
      }
    }
  }

  depends_on = [aws_s3_bucket_policy.trail]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# CloudWatch Metric Filters + Alarms (Secrets Manager monitoring)
# ---------------------------------------------------------------------------

resource "aws_cloudwatch_log_metric_filter" "secrets_access" {
  count = local.create && var.enable_cloudwatch && var.enable_secrets_alarms ? 1 : 0

  name           = "${var.trail_name}-secrets-access"
  log_group_name = aws_cloudwatch_log_group.trail[0].name
  pattern        = "{ ($.eventName = GetSecretValue) || ($.eventName = PutSecretValue) || ($.eventName = CreateSecret) || ($.eventName = DeleteSecret) }"

  metric_transformation {
    name          = "SecretsManagerAccessCount"
    namespace     = "CloudTrail/SecretsManager"
    value         = "1"
    default_value = "0"
  }
}

resource "aws_cloudwatch_metric_alarm" "secrets_write" {
  count = local.create && var.enable_cloudwatch && var.enable_secrets_alarms ? 1 : 0

  alarm_name          = "${var.trail_name}-secrets-write-activity"
  alarm_description   = "Secrets Manager write activity detected (PutSecretValue, CreateSecret, DeleteSecret)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "SecretsManagerAccessCount"
  namespace           = "CloudTrail/SecretsManager"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"

  tags = var.tags
}
