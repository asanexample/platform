data "aws_caller_identity" "current" {
  count = var.create ? 1 : 0
}

locals {
  oidc_provider_url = "token.actions.githubusercontent.com"
  audience          = "sts.amazonaws.com"

  repos = length(var.github_repos) > 0 ? var.github_repos : [var.github_repo]

  subject_claims = concat(
    flatten([
      for repo in local.repos : [
        for branch in var.github_branches :
        # Auto-prefix bare branch names with refs/heads/; pass through full ref paths unchanged
        "repo:${var.github_org}/${repo}:ref:${
          startswith(branch, "refs/") ? branch : "refs/heads/${branch}"
        }"
      ]
    ]),
    flatten([
      for repo in local.repos : [
        for event in var.github_events :
        "repo:${var.github_org}/${repo}:${event}"
      ]
    ]),
  )
}

# ---------------------------------------------------------------------------
# OIDC Provider
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create ? 1 : 0

  url            = "https://${local.oidc_provider_url}"
  client_id_list = [local.audience]
  # AWS no longer validates GitHub OIDC thumbprints (since July 2023); dummy value required by API
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]

  tags = var.tags
}

data "aws_iam_policy_document" "trust" {
  count = var.create ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [aws_iam_openid_connect_provider.github[0].arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${local.oidc_provider_url}:aud"
      values   = [local.audience]
    }

    condition {
      test     = "StringLike"
      variable = "${local.oidc_provider_url}:sub"
      values   = local.subject_claims
    }
  }
}

# ---------------------------------------------------------------------------
# IAM Role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "this" {
  count = var.create ? 1 : 0

  name                 = var.role_name
  assume_role_policy   = data.aws_iam_policy_document.trust[0].json
  max_session_duration = var.max_session_duration

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = var.create ? toset(var.role_policy_arns) : toset([])

  role       = aws_iam_role.this[0].name
  policy_arn = each.value
}

resource "aws_iam_role_policy" "inline" {
  count = var.create && var.inline_policy != "" ? 1 : 0

  name   = "${var.role_name}-inline"
  role   = aws_iam_role.this[0].id
  policy = var.inline_policy
}
