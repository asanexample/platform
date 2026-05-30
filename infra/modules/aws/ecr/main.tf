locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# Repositories
# ---------------------------------------------------------------------------

# Tag mutability is per-repo configurable (var.repositories[*].tag_mutability). Supply-chain
# integrity is enforced by digest-pinning + cosign signing + Kyverno immutable-tag admission on
# workloads, not by repo-level immutability. Immutable ECR tags tracked as hardening (#119).
# nosemgrep: terraform.aws.security.aws-ecr-mutable-image-tags.aws-ecr-mutable-image-tags
resource "aws_ecr_repository" "this" {
  for_each = local.create ? var.repositories : {}

  name                 = each.key
  image_tag_mutability = each.value.tag_mutability
  force_delete         = var.force_delete

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    encryption_type = "AES256"
  }

  tags = merge(var.tags, each.value.tags)
}

# ---------------------------------------------------------------------------
# Cross-Account Pull Policy
# ---------------------------------------------------------------------------

resource "aws_ecr_repository_policy" "cross_account_pull" {
  for_each = local.create && length(var.pull_account_ids) > 0 ? var.repositories : {}

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CrossAccountPull"
        Effect = "Allow"
        Principal = {
          # Region is intentionally empty in IAM ARNs (IAM is a global service)
          AWS = [for id in var.pull_account_ids : "arn:aws:iam::${id}:root"]
        }
        Action = [
          "ecr:BatchGetImage",
          "ecr:GetDownloadUrlForLayer",
          "ecr:BatchCheckLayerAvailability",
        ]
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Lifecycle Policy
# ---------------------------------------------------------------------------

resource "aws_ecr_lifecycle_policy" "this" {
  for_each = local.create ? var.repositories : {}

  repository = aws_ecr_repository.this[each.key].name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 7 days"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 7
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep last ${var.max_image_count} tagged images"
        selection = {
          tagStatus      = "tagged"
          tagPatternList = ["*"]
          countType      = "imageCountMoreThan"
          countNumber    = var.max_image_count
        }
        action = {
          type = "expire"
        }
      },
    ]
  })
}
