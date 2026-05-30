# ---------------------------------------------------------------------------
# S3 buckets (private, encrypted) with optional cross-account read/write grants
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "this" {
  for_each = var.create ? var.buckets : {}

  bucket = each.key
  tags   = merge(var.tags, each.value.tags)
}

# Hard-block all public access (defense in depth alongside the scoped bucket policy).
resource "aws_s3_bucket_public_access_block" "this" {
  for_each = var.create ? var.buckets : {}

  bucket                  = aws_s3_bucket.this[each.key].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# Bucket-owner-enforced: ACLs disabled, access is policy-only (clean for cross-account reads — the
# bucket owner owns all objects, and the cross-account role's access is governed purely by the policies).
resource "aws_s3_bucket_ownership_controls" "this" {
  for_each = var.create ? var.buckets : {}

  bucket = aws_s3_bucket.this[each.key].id
  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# SSE-S3 (AES256) — avoids cross-account KMS key-policy grants. Switch to aws:kms only if a regulated
# tier requires it (then the key policy must also grant the cross-account reader role).
resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  for_each = var.create ? var.buckets : {}

  bucket = aws_s3_bucket.this[each.key].id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

# ---------------------------------------------------------------------------
# Cross-account access — resource (bucket) side of the grant
# ---------------------------------------------------------------------------
# Cross-account S3 from an IAM role requires BOTH the caller's identity policy (granted on the team role
# elsewhere) AND this bucket policy. Scoped to the exact role ARNs, not an account :root.

locals {
  policied_buckets = var.create ? {
    for name, cfg in var.buckets : name => cfg
    if length(cfg.reader_role_arns) + length(cfg.writer_role_arns) > 0
  } : {}
}

data "aws_iam_policy_document" "bucket" {
  for_each = local.policied_buckets

  dynamic "statement" {
    for_each = length(each.value.reader_role_arns) > 0 ? [1] : []
    content {
      sid       = "CrossAccountRead"
      effect    = "Allow"
      actions   = ["s3:GetObject"]
      resources = ["${aws_s3_bucket.this[each.key].arn}/*"]
      principals {
        type        = "AWS"
        identifiers = each.value.reader_role_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(each.value.reader_role_arns) > 0 ? [1] : []
    content {
      sid       = "CrossAccountList"
      effect    = "Allow"
      actions   = ["s3:ListBucket"]
      resources = [aws_s3_bucket.this[each.key].arn]
      principals {
        type        = "AWS"
        identifiers = each.value.reader_role_arns
      }
    }
  }

  dynamic "statement" {
    for_each = length(each.value.writer_role_arns) > 0 ? [1] : []
    content {
      sid       = "CrossAccountWrite"
      effect    = "Allow"
      actions   = ["s3:PutObject", "s3:DeleteObject"]
      resources = ["${aws_s3_bucket.this[each.key].arn}/*"]
      principals {
        type        = "AWS"
        identifiers = each.value.writer_role_arns
      }
    }
  }
}

resource "aws_s3_bucket_policy" "this" {
  for_each = local.policied_buckets

  bucket = aws_s3_bucket.this[each.key].id
  policy = data.aws_iam_policy_document.bucket[each.key].json

  # The bucket policy references cross-account role ARNs; PutBucketPolicy validates same-account
  # principals, so the policy depends on PAB being set first (ordering safety within the module).
  depends_on = [aws_s3_bucket_public_access_block.this]
}
