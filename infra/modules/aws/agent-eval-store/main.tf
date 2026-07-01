# ---------------------------------------------------------------------------
# Agent-eval corpus — durable forward-capture store (ADR-080 D6 / ADR-086)
# ---------------------------------------------------------------------------
# The always-on, keep-forever home for the triage agent's captured evaluation
# fixtures ({alert-group, telemetry snapshot, structured label, rubric}). The
# corpus must be built FORWARD — telemetry retention is short, so an incident
# not captured when it happens is lost — and it later feeds the shadow→proven→
# promoted graduation signal that gates agent autonomy. It holds potentially-
# sensitive telemetry forever AND is replayed into an LLM, so it is hardened:
# TLS-only access, full public-access block, versioning, and integrity controls
# (the writer gets no DeleteObject; Object Lock is a seam). Encryption is SSE-S3
# by default (the house baseline) and upgradable to a dedicated CMK via
# `use_kms_cmk` (the "regulated-tier upgrade") — wired to the cost profile at the
# unit. The agent's WRITE grant is identity-based (its XAgent claim), not here, to
# avoid a chicken-and-egg on the Composition-minted role ARN.

data "aws_caller_identity" "current" {}

locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# KMS — corpus envelope-encryption CMK (only when use_kms_cmk; else SSE-S3)
# ---------------------------------------------------------------------------

resource "aws_kms_key" "corpus" {
  count = local.create && var.use_kms_cmk ? 1 : 0

  description             = "Envelope encryption for the agent-eval corpus (${var.bucket_name})"
  enable_key_rotation     = true
  deletion_window_in_days = var.kms_deletion_window_days
  policy                  = data.aws_iam_policy_document.kms[0].json

  tags = var.tags
}

resource "aws_kms_alias" "corpus" {
  count = local.create && var.use_kms_cmk ? 1 : 0

  name          = "alias/${var.bucket_name}"
  target_key_id = aws_kms_key.corpus[0].key_id
}

data "aws_iam_policy_document" "kms" {
  count = local.create && var.use_kms_cmk ? 1 : 0

  # Root-enable: lets account IAM policies (the agent's claim grant) delegate key
  # use in-account, the standard CMK key-policy baseline.
  statement {
    sid       = "EnableIAMUserPermissions"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]

    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Cross-account readers (future CI replay/grader) need an explicit key grant.
  dynamic "statement" {
    for_each = length(var.reader_role_arns) > 0 ? [1] : []

    content {
      sid       = "AllowReaderDecrypt"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = ["*"]

      principals {
        type        = "AWS"
        identifiers = var.reader_role_arns
      }
    }
  }
}

# ---------------------------------------------------------------------------
# S3 — corpus bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "corpus" {
  count = local.create ? 1 : 0

  bucket              = var.bucket_name
  force_destroy       = var.force_destroy
  object_lock_enabled = var.object_lock_enabled

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "corpus" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "corpus" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "corpus" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "corpus" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm     = var.use_kms_cmk ? "aws:kms" : "AES256"
      kms_master_key_id = one(aws_kms_key.corpus[*].arn)
    }
    bucket_key_enabled = var.use_kms_cmk
  }
}

# Optional tiering of aged fixtures to Standard-IA (replay tolerates slow reads).
resource "aws_s3_bucket_lifecycle_configuration" "corpus" {
  count = local.create && var.transition_to_ia_days > 0 ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id

  rule {
    id     = "tier-aged-fixtures-to-ia"
    status = "Enabled"

    filter {}

    transition {
      days          = var.transition_to_ia_days
      storage_class = "STANDARD_IA"
    }
  }

  depends_on = [aws_s3_bucket_versioning.corpus]
}

# ---------------------------------------------------------------------------
# S3 — bucket policy (TLS-only baseline + optional cross-account reader grant)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket_policy" "corpus" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.corpus[0].id
  policy = data.aws_iam_policy_document.bucket[0].json

  depends_on = [aws_s3_bucket_public_access_block.corpus]
}

data "aws_iam_policy_document" "bucket" {
  count = local.create ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.corpus[0].arn, "${aws_s3_bucket.corpus[0].arn}/*"]

    principals {
      type        = "AWS"
      identifiers = ["*"]
    }

    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }

  # Resource side of a cross-account reader grant (the reader also needs a
  # matching identity policy); the writer (agent) is granted via its claim.
  dynamic "statement" {
    for_each = length(var.reader_role_arns) > 0 ? [1] : []

    content {
      sid       = "AllowReaderRead"
      effect    = "Allow"
      actions   = ["s3:GetObject", "s3:ListBucket"]
      resources = [aws_s3_bucket.corpus[0].arn, "${aws_s3_bucket.corpus[0].arn}/*"]

      principals {
        type        = "AWS"
        identifiers = var.reader_role_arns
      }
    }
  }
}
