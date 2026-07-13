# ---------------------------------------------------------------------------
# IAM role for the Mimir ServiceAccount (S3 blocks access); AWS identity via EKS Pod Identity (ADR-047)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "mimir_trust" {
  count = local.create ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "mimir" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-mimir-"
  assume_role_policy = data.aws_iam_policy_document.mimir_trust[0].json
  tags               = var.tags
}

# AES256 bucket => no KMS statement needed (unlike an SSE-KMS bucket, which would require
# kms:GenerateDataKey*/Decrypt or writes fail with AccessDenied). Scoped to the blocks bucket only.
resource "aws_iam_role_policy" "mimir_s3" {
  count = local.create ? 1 : 0

  name = "blocks-storage"
  role = aws_iam_role.mimir[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListBucket"
        Effect   = "Allow"
        Action   = ["s3:ListBucket"]
        Resource = [aws_s3_bucket.blocks[0].arn]
      },
      {
        Sid      = "ObjectRW"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = ["${aws_s3_bucket.blocks[0].arn}/*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "mimir" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.mimir[0].arn
  tags            = var.tags
}
