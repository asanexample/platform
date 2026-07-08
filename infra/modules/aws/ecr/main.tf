locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# Repositories
# ---------------------------------------------------------------------------

# Tag mutability is per-repo configurable (var.repositories[*].tag_mutability); team repos default
# to IMMUTABLE. Use IMMUTABLE_WITH_EXCLUSION to keep IMAGE tags immutable while letting cosign update
# its `sha256-*.sig`/`.att` auxiliary tags — required so an image can carry multiple attestations
# (SBOM + SLSA provenance) on an immutable repo (#114). The exclusion never touches image tags
# (commit SHAs), only cosign's sha256-* tags.
# nosemgrep: terraform.aws.security.aws-ecr-mutable-image-tags.aws-ecr-mutable-image-tags
resource "aws_ecr_repository" "this" {
  for_each = local.create ? var.repositories : {}

  name                 = each.key
  image_tag_mutability = each.value.tag_mutability
  force_delete         = var.force_delete

  dynamic "image_tag_mutability_exclusion_filter" {
    for_each = each.value.tag_mutability == "IMMUTABLE_WITH_EXCLUSION" ? var.tag_mutability_exclusion_filters : []
    content {
      filter      = image_tag_mutability_exclusion_filter.value
      filter_type = "WILDCARD"
    }
  }

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
# Pull-Through Cache Rules
# ---------------------------------------------------------------------------
# Registry-level (not per-repo) rules that mirror public registries into this account on first pull, so
# cluster/CI base-image pulls hit our own ECR (IAM auth, no Docker Hub rate limits) instead of the public
# internet. The cache repo (`<prefix>/<image>`) is auto-created on first pull — the pulling principal needs
# ecr:BatchImportUpstreamImage + ecr:CreateRepository. ADR-098 D2.

resource "aws_ecr_pull_through_cache_rule" "this" {
  for_each = local.create ? var.pull_through_cache_rules : {}

  ecr_repository_prefix = each.key
  upstream_registry_url = each.value.upstream_registry_url
  credential_arn        = each.value.credential_arn
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
