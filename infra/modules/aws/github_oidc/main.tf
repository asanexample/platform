locals {
  oidc_provider_url = "token.actions.githubusercontent.com"
  audience          = "sts.amazonaws.com"

  # Per-role OIDC subject claims: repo × branch (ref) plus repo × event.
  subject_claims_by_role = {
    for role_key, role in var.roles : role_key => concat(
      flatten([
        for repo in role.repos : [
          for branch in role.branches :
          # Auto-prefix bare branch names with refs/heads/; pass full ref paths through unchanged
          "repo:${var.github_org}/${repo}:ref:${
            startswith(branch, "refs/") ? branch : "refs/heads/${branch}"
          }"
        ]
      ]),
      flatten([
        for repo in role.repos : [
          for event in role.events :
          "repo:${var.github_org}/${repo}:${event}"
        ]
      ]),
    )
  }

  # Flatten role -> managed policy attachments into a single keyed map.
  role_policy_attachments = merge([
    for role_key, role in var.roles : {
      for policy_arn in role.role_policy_arns :
      "${role_key}/${basename(policy_arn)}" => { role = role_key, policy_arn = policy_arn }
    }
  ]...)
}

# ---------------------------------------------------------------------------
# OIDC Provider (account singleton)
# ---------------------------------------------------------------------------

resource "aws_iam_openid_connect_provider" "github" {
  count = var.create ? 1 : 0

  url            = "https://${local.oidc_provider_url}"
  client_id_list = [local.audience]
  # AWS no longer validates GitHub OIDC thumbprints (since July 2023); dummy value required by API
  thumbprint_list = ["ffffffffffffffffffffffffffffffffffffffff"]

  tags = var.tags
}

# ---------------------------------------------------------------------------
# IAM Roles (one per entry in var.roles)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "trust" {
  for_each = var.create ? var.roles : {}

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
      values   = local.subject_claims_by_role[each.key]
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = var.create ? var.roles : {}

  name                 = each.key
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json
  max_session_duration = each.value.max_session_duration

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "managed" {
  for_each = var.create ? local.role_policy_attachments : {}

  role       = aws_iam_role.this[each.value.role].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "inline" {
  for_each = var.create ? { for k, r in var.roles : k => r if r.inline_policy != null } : {}

  name   = "${each.key}-inline"
  role   = aws_iam_role.this[each.key].id
  policy = each.value.inline_policy
}
