locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  external_dns_values = {
    provider = {
      name = "aws"
    }

    sources = var.sources

    domainFilters = var.domain_filters

    txtOwnerId = var.cluster_name # TXT owner ID prevents record conflicts when multiple clusters share a hosted zone

    policy = var.policy

    podLabels = local.k8s_labels

    serviceAccount = {
      annotations = local.create_irsa ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_dns[0].arn
      } : {}
    }
  }
}

# ---------------------------------------------------------------------------
# IRSA — IAM Role for external-dns (Route53 record management)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "external_dns_trust" {
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
      values   = ["system:serviceaccount:${var.namespace}:external-dns"]
    }
  }
}

resource "aws_iam_role" "external_dns" {
  count = local.create_irsa ? 1 : 0

  name_prefix        = "${var.cluster_name}-ext-dns-"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "external_dns_route53" {
  count = local.create_irsa ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "route53:ChangeResourceRecordSets",
    ]
    resources = [var.route53_hosted_zone_arn]
  }

  statement {
    effect = "Allow"
    actions = [
      "route53:ListHostedZones",
      "route53:ListResourceRecordSets",
      "route53:ListTagsForResource",
    ]
    resources = ["*"] # List actions don't support resource-level scoping in Route53 IAM
  }
}

resource "aws_iam_role_policy" "external_dns_route53" {
  count = local.create_irsa ? 1 : 0

  name   = "route53-records"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns_route53[0].json
}

# ---------------------------------------------------------------------------
# Helm Release
# ---------------------------------------------------------------------------

resource "helm_release" "external_dns" {
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
  replace          = true # Delete + reinstall if the release is stuck in a failed state

  values = [
    yamlencode(local.external_dns_values),
  ]

  depends_on = [aws_iam_role.external_dns]
}
