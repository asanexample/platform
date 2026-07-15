# ---------------------------------------------------------------------------
# S3 — Mimir blocks storage (SSE-S3/AES256, mirrors infra/modules/aws/s3)
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "blocks" {
  count = local.create ? 1 : 0

  bucket_prefix = "${var.cluster_name}-mimir-blocks-"
  force_destroy = var.force_destroy
  tags          = var.tags
}

resource "aws_s3_bucket_ownership_controls" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "blocks" {
  count = local.create ? 1 : 0

  bucket                  = aws_s3_bucket.blocks[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_server_side_encryption_configuration" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

resource "aws_s3_bucket_versioning" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id
  versioning_configuration { status = "Enabled" }
}

# Mimir's compactor manages object lifecycle; versioning exists only to satisfy the security baseline.
# Expire noncurrent versions fast + abort dangling multipart uploads so the bucket doesn't grow unbounded.
resource "aws_s3_bucket_lifecycle_configuration" "blocks" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.blocks[0].id

  rule {
    id     = "expire-noncurrent"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = 1 }
    abort_incomplete_multipart_upload { days_after_initiation = 1 }
  }
}
