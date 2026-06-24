locals {
  create = var.create

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

    # AWS identity via EKS Pod Identity (ADR-047): the SA is matched by the pod-identity
    # association below — no IRSA `eks.amazonaws.com/role-arn` annotation needed.
  }
}

# ---------------------------------------------------------------------------
# IAM — external-dns role (Route53 records); AWS identity via EKS Pod Identity (ADR-047)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "external_dns_trust" {
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

resource "aws_iam_role" "external_dns" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-ext-dns-"
  assume_role_policy = data.aws_iam_policy_document.external_dns_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "external_dns_route53" {
  count = local.create ? 1 : 0

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
  count = local.create ? 1 : 0

  name   = "route53-records"
  role   = aws_iam_role.external_dns[0].id
  policy = data.aws_iam_policy_document.external_dns_route53[0].json
}

# Pod Identity association: binds the role to the `external-dns` ServiceAccount (the chart's SA name)
# in this namespace. The pod-identity agent injects creds at pod launch — no SA annotation, no OIDC trust.
resource "aws_eks_pod_identity_association" "external_dns" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "external-dns"
  role_arn        = aws_iam_role.external_dns[0].arn
  tags            = var.tags
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

  # The association must exist before the SA/pod rolls so the new pod gets Pod-Identity creds immediately.
  depends_on = [aws_eks_pod_identity_association.external_dns]
}
