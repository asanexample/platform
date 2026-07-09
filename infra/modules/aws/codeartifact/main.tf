locals {
  create          = var.create
  cross_account   = local.create && length(var.read_account_ids) > 0
  create_kms      = local.create && var.kms_key_arn == ""
  domain_key_arn  = local.create_kms ? aws_kms_key.domain[0].arn : var.kms_key_arn
  read_principals = [for id in var.read_account_ids : "arn:aws:iam::${id}:root"]

  # Standard CodeArtifact read (pull) action set, granted to cross-account principals on consumer repos.
  repository_read_actions = [
    "codeartifact:DescribePackageVersion",
    "codeartifact:DescribeRepository",
    "codeartifact:GetPackageVersionAsset",
    "codeartifact:GetPackageVersionReadme",
    "codeartifact:GetRepositoryEndpoint",
    "codeartifact:ListPackages",
    "codeartifact:ListPackageVersionAssets",
    "codeartifact:ListPackageVersionDependencies",
    "codeartifact:ListPackageVersions",
    "codeartifact:ReadFromRepository",
  ]
}

data "aws_caller_identity" "current" {}

# ---------------------------------------------------------------------------
# KMS — Domain Asset Encryption
# ---------------------------------------------------------------------------
# CodeArtifact encrypts every asset in the domain with this key. Cross-account readers must be able
# to decrypt, so the key policy grants Decrypt/DescribeKey to var.read_account_ids alongside the
# domain-owner root. Omitted (var.kms_key_arn set) to reuse an existing key.

resource "aws_kms_key" "domain" {
  count = local.create_kms ? 1 : 0

  description             = "CodeArtifact domain asset encryption (${var.domain_name})"
  enable_key_rotation     = true
  deletion_window_in_days = 7

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "EnableRootAccountAdmin"
          Effect    = "Allow"
          Principal = { AWS = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:root" }
          Action    = "kms:*"
          Resource  = "*"
        }
      ],
      local.cross_account ? [
        {
          Sid       = "CrossAccountDecrypt"
          Effect    = "Allow"
          Principal = { AWS = local.read_principals }
          Action = [
            "kms:Decrypt",
            "kms:DescribeKey",
            "kms:GenerateDataKey",
          ]
          Resource = "*"
        }
      ] : []
    )
  })

  tags = var.tags
}

resource "aws_kms_alias" "domain" {
  count = local.create_kms ? 1 : 0

  name          = "alias/codeartifact-${var.domain_name}"
  target_key_id = aws_kms_key.domain[0].key_id
}

# ---------------------------------------------------------------------------
# Domain
# ---------------------------------------------------------------------------

resource "aws_codeartifact_domain" "this" {
  count = local.create ? 1 : 0

  domain         = var.domain_name
  encryption_key = local.domain_key_arn

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Cross-Account Domain Permissions Policy
# ---------------------------------------------------------------------------
# Domain-scoped grant so reader accounts can obtain an auth token + resolve endpoints. Repository-level
# read is granted separately on each consumer repo (below).

resource "aws_codeartifact_domain_permissions_policy" "cross_account" {
  count = local.cross_account ? 1 : 0

  domain = aws_codeartifact_domain.this[0].domain

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CrossAccountDomainRead"
        Effect    = "Allow"
        Principal = { AWS = local.read_principals }
        Action = [
          "codeartifact:GetAuthorizationToken",
          "codeartifact:GetDomainPermissionsPolicy",
          "codeartifact:ListRepositoriesInDomain",
        ]
        Resource = "*"
      }
    ]
  })
}

# ---------------------------------------------------------------------------
# Store Repositories (Public Upstream Proxies)
# ---------------------------------------------------------------------------
# One external connection per repository (an AWS limit) — proxy each public source via its own store
# repo, then reference them as upstreams from consumer repositories.

resource "aws_codeartifact_repository" "store" {
  for_each = local.create ? var.store_repositories : {}

  repository  = each.key
  domain      = aws_codeartifact_domain.this[0].domain
  description = each.value.description

  external_connections {
    external_connection_name = each.value.external_connection
  }

  tags = merge(var.tags, each.value.tags)
}

# ---------------------------------------------------------------------------
# Consumer Repositories (per-Team/Product)
# ---------------------------------------------------------------------------

resource "aws_codeartifact_repository" "this" {
  for_each = local.create ? var.repositories : {}

  repository  = each.key
  domain      = aws_codeartifact_domain.this[0].domain
  description = each.value.description

  dynamic "upstream" {
    for_each = each.value.upstreams
    content {
      repository_name = upstream.value
    }
  }

  tags = merge(var.tags, each.value.tags)

  # Upstreams are referenced by name; ensure the store repos they point at exist first.
  depends_on = [aws_codeartifact_repository.store]
}

# ---------------------------------------------------------------------------
# Cross-Account Repository Read Policy
# ---------------------------------------------------------------------------

resource "aws_codeartifact_repository_permissions_policy" "cross_account_read" {
  for_each = local.cross_account ? var.repositories : {}

  domain     = aws_codeartifact_domain.this[0].domain
  repository = aws_codeartifact_repository.this[each.key].repository

  policy_document = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "CrossAccountRead"
        Effect    = "Allow"
        Principal = { AWS = local.read_principals }
        Action    = local.repository_read_actions
        Resource  = "*"
      }
    ]
  })
}
