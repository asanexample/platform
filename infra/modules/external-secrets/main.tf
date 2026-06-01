locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  external_secrets_values = {
    installCRDs = true # CRDs installed via Helm; Helm won't remove CRDs on uninstall

    podLabels = local.k8s_labels

    serviceAccount = {
      annotations = local.create_irsa ? {
        "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets[0].arn
      } : {}
    }

    # Prometheus metrics: expose the controller metrics Service + a ServiceMonitor (needs the
    # Prometheus-operator CRDs from the observability hub, #102). Off by default.
    metrics        = { service = { enabled = var.metrics_enabled } }
    serviceMonitor = { enabled = var.metrics_enabled }

    # EKS + Cilium overlay (cluster-pool): the EKS managed control plane can't route to overlay pod
    # IPs, so the validating webhook server runs on hostNetwork (node VPC IP). port moves off 10250
    # (kubelet) and off cert-manager's 10260 to avoid host-port clashes if they co-locate on a node.
    webhook = {
      hostNetwork = var.webhook_host_network
      port        = var.webhook_host_network ? 10261 : 10250
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
    # Wildcard region allows access to secrets replicated across regions
    resources = ["arn:aws:secretsmanager:*:${var.aws_account_id}:secret:${var.secret_path_prefix}/*"]
  }

  statement {
    effect = "Allow"
    actions = [
      "ssm:GetParameter",
      "ssm:GetParameters",
      "ssm:GetParametersByPath",
    ]
    # ssm_path_prefix must start with "/" (SSM ARN format: parameter/<path>)
    resources = ["arn:aws:ssm:*:${var.aws_account_id}:parameter${var.ssm_path_prefix}/*"]
  }

  dynamic "statement" {
    for_each = length(var.kms_key_arns) > 0 ? [1] : []
    content {
      effect = "Allow"
      actions = [
        "kms:Decrypt",
      ]
      resources = var.kms_key_arns
    }
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
