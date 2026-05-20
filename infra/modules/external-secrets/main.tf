locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  external_secrets_values = {
    installCRDs = true

    podLabels = local.k8s_labels

    serviceAccount = {
      annotations = local.create_irsa ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets[0].arn
      } : {}
    }
  }
}

# ---------------------------------------------------------------------------
# IRSA — IAM Role for external-secrets (AWS Secrets Manager + SSM)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "external_secrets_trust" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${var.namespace}:external-secrets"]
    }
  }
}

resource "aws_iam_role" "external_secrets" {
  count = local.create_irsa ? 1 : 0

  name_prefix        = "${var.cluster_name}-ext-sec-"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "external_secrets" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "secretsmanager:GetSecretValue",
      "secretsmanager:DescribeSecret",
      "secretsmanager:ListSecretVersionIds",
    ]
    resources = ["arn:aws:secretsmanager:*:${var.aws_account_id}:secret:*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    resources = ["arn:aws:ssm:*:${var.aws_account_id}:parameter/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "kms:Decrypt",
    ]
    resources = var.kms_key_arns
  }
}

resource "aws_iam_role_policy" "external_secrets" {
  count = local.create_irsa ? 1 : 0

  name   = "secrets-access"
  role   = aws_iam_role.external_secrets[0].id
  policy = data.aws_iam_policy_document.external_secrets[0].json
}

# ---------------------------------------------------------------------------
# Helm Release
# ---------------------------------------------------------------------------

resource "helm_release" "external_secrets" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
  replace          = true

  values = [
    yamlencode(local.external_secrets_values),
  ]

  depends_on = [aws_iam_role.external_secrets]
}
