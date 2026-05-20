locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  cert_manager_values = {
    installCRDs = true

    global = {
      podLabels = local.k8s_labels
    }

    serviceAccount = {
      annotations = local.create_irsa ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.cert_manager[0].arn
      } : {}
    }

    securityContext = {
      fsGroup = 1001
    }
  }
}

# ---------------------------------------------------------------------------
# IRSA — IAM Role for cert-manager (DNS01 challenge via Route53)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cert_manager_trust" {
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
      values   = ["system:serviceaccount:${var.namespace}:cert-manager"]
    }
  }
}

resource "aws_iam_role" "cert_manager" {
  count = local.create_irsa ? 1 : 0

  name_prefix        = "${var.cluster_name}-cert-mgr-"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "cert_manager_route53" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "route53:GetChange",
    ]
    resources = ["arn:aws:route53:::change/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
      "route53:ListResourceRecordSets",
    ]
    resources = [var.route53_hosted_zone_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  count = local.create_irsa ? 1 : 0

  name   = "route53-dns01"
  role   = aws_iam_role.cert_manager[0].id
  policy = data.aws_iam_policy_document.cert_manager_route53[0].json
}

# ---------------------------------------------------------------------------
# Helm Release
# ---------------------------------------------------------------------------

resource "helm_release" "cert_manager" {
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
    yamlencode(local.cert_manager_values),
  ]

  depends_on = [aws_iam_role.cert_manager]
}
