# ---------------------------------------------------------------------------
# CloudNativePG backups — shared S3 store + per-cluster least-privilege IAM
# ---------------------------------------------------------------------------
# The durable off-cluster home for CNPG base backups + continuous WAL archiving
# (point-in-time recovery). One hardened bucket (TLS-only, PAB, versioned,
# SSE-S3) with a per-cluster key prefix; each CNPG cluster gets its OWN IAM role
# scoped to its OWN prefix (a Keycloak-DB backup role can't touch the Backstage
# prefix), bound to the cluster's instance ServiceAccount via EKS Pod Identity
# (ADR-041/047 — no IRSA annotation). The Barman Cloud plugin's ObjectStore uses
# `inheritFromIAMRole`, so these creds are what it writes with. Barman manages
# base-backup/WAL RETENTION itself (ObjectStore.retentionPolicy); the S3
# lifecycle here is only hygiene (abort stale MPUs, expire old noncurrent
# versions). See #1119 / the alerting-blindspot epic #1124.

locals {
  create   = var.create
  clusters = local.create ? { for c in var.clusters : c.name => c } : {}
}

# ---------------------------------------------------------------------------
# S3 — backup bucket
# ---------------------------------------------------------------------------

resource "aws_s3_bucket" "backups" {
  count = local.create ? 1 : 0

  bucket        = var.bucket_name
  force_destroy = var.force_destroy

  tags = var.tags
}

resource "aws_s3_bucket_ownership_controls" "backups" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id
  rule { object_ownership = "BucketOwnerEnforced" }
}

resource "aws_s3_bucket_public_access_block" "backups" {
  count = local.create ? 1 : 0

  bucket                  = aws_s3_bucket.backups[0].id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "backups" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id
  versioning_configuration { status = "Enabled" }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "backups" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id
  rule {
    apply_server_side_encryption_by_default { sse_algorithm = "AES256" }
  }
}

# Hygiene only — Barman owns backup retention (ObjectStore.retentionPolicy).
resource "aws_s3_bucket_lifecycle_configuration" "backups" {
  count = local.create ? 1 : 0

  bucket = aws_s3_bucket.backups[0].id

  rule {
    id     = "abort-incomplete-multipart"
    status = "Enabled"
    filter {}
    abort_incomplete_multipart_upload { days_after_initiation = 7 }
  }

  rule {
    id     = "expire-noncurrent-versions"
    status = "Enabled"
    filter {}
    noncurrent_version_expiration { noncurrent_days = var.noncurrent_version_expiration_days }
  }

  depends_on = [aws_s3_bucket_versioning.backups]
}

# TLS-only baseline.
resource "aws_s3_bucket_policy" "backups" {
  count = local.create ? 1 : 0

  bucket     = aws_s3_bucket.backups[0].id
  policy     = data.aws_iam_policy_document.bucket[0].json
  depends_on = [aws_s3_bucket_public_access_block.backups]
}

data "aws_iam_policy_document" "bucket" {
  count = local.create ? 1 : 0

  statement {
    sid       = "DenyInsecureTransport"
    effect    = "Deny"
    actions   = ["s3:*"]
    resources = [aws_s3_bucket.backups[0].arn, "${aws_s3_bucket.backups[0].arn}/*"]
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
}

# ---------------------------------------------------------------------------
# IAM — one least-privilege role per cluster (Pod Identity), scoped to its prefix
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  count = local.create ? 1 : 0

  # EKS Pod Identity trust (ADR-047) — the association below is what actually binds it to the SA.
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cluster" {
  for_each = local.clusters

  name               = "${var.role_name_prefix}-${each.value.name}"
  assume_role_policy = data.aws_iam_policy_document.trust[0].json
  tags               = var.tags
}

data "aws_iam_policy_document" "cluster" {
  for_each = local.clusters

  # List only within this cluster's own prefix.
  statement {
    sid       = "ListOwnPrefix"
    effect    = "Allow"
    actions   = ["s3:ListBucket", "s3:ListBucketMultipartUploads", "s3:GetBucketLocation"]
    resources = [aws_s3_bucket.backups[0].arn]
    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["${each.value.name}/*", each.value.name]
    }
  }

  # Read/write/delete (Barman needs Delete for its own retention) within the prefix only.
  statement {
    sid    = "RWOwnPrefix"
    effect = "Allow"
    actions = [
      "s3:PutObject", "s3:GetObject", "s3:DeleteObject",
      "s3:AbortMultipartUpload", "s3:ListMultipartUploadParts",
    ]
    resources = ["${aws_s3_bucket.backups[0].arn}/${each.value.name}/*"]
  }
}

resource "aws_iam_role_policy" "cluster" {
  for_each = local.clusters

  name   = "s3-backups"
  role   = aws_iam_role.cluster[each.key].id
  policy = data.aws_iam_policy_document.cluster[each.key].json
}

# ---------------------------------------------------------------------------
# EKS Pod Identity — bind each cluster's instance SA to its role
# ---------------------------------------------------------------------------

resource "aws_eks_pod_identity_association" "cluster" {
  for_each = local.clusters

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = aws_iam_role.cluster[each.key].arn

  tags = var.tags
}
