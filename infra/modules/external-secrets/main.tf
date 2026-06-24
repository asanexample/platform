locals {
  create = var.create

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  external_secrets_values = {
    installCRDs = true # CRDs installed via Helm; Helm won't remove CRDs on uninstall

    podLabels = local.k8s_labels

    # AWS identity via EKS Pod Identity (ADR-047): the external-secrets controller SA is matched by the
    # pod-identity association below. The ClusterSecretStores (secret-stores module) drop their
    # `auth.jwt.serviceAccountRef` and use this controller identity — no IRSA annotation, no OIDC.

    # Prometheus metrics: expose the controller metrics Service + a ServiceMonitor (needs the
    # Prometheus-operator CRDs from the observability hub, #102). Off by default.
    metrics        = { service = { enabled = var.metrics_enabled } }
    serviceMonitor = { enabled = var.metrics_enabled }

    # EKS + Cilium overlay (cluster-pool): the EKS managed control plane can't route to overlay pod
    # IPs, so the validating webhook server runs on hostNetwork (node VPC IP). On hostNetwork the
    # serving port AND the metrics port become host ports — move both off defaults (10250 kubelet,
    # 8080 which collides on busy nodes) to a private 1026x range distinct from cert-manager's 10260.
    webhook = {
      hostNetwork = var.webhook_host_network
      port        = var.webhook_host_network ? 10261 : 10250
      # Fail-open: the validating webhook fires on ExternalSecret CREATE/UPDATE *and DELETE*, so if its backend
      # is unavailable (e.g. the webhook pod is Pending/evicted under teardown node pressure) a default
      # failurePolicy=Fail blocks DELETION of every ExternalSecret — "no endpoints available for service
      # external-secrets-webhook" — and strands the owning units (dex/keycloak/oauth2-proxy/backstage) on
      # teardown. A down admission webhook must never brick the resource lifecycle; Ignore lets deletes proceed.
      failurePolicy = "Ignore"
      metrics = {
        listen = {
          port = var.webhook_host_network ? 10262 : 8080
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — external-secrets role (Secrets Manager + SSM); AWS identity via EKS Pod Identity (ADR-047)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "external_secrets_trust" {
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

resource "aws_iam_role" "external_secrets" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-ext-sec-"
  assume_role_policy = data.aws_iam_policy_document.external_secrets_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "external_secrets" {
  count = local.create ? 1 : 0

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
  count = local.create ? 1 : 0

  name   = "secrets-access"
  role   = aws_iam_role.external_secrets[0].id
  policy = data.aws_iam_policy_document.external_secrets[0].json
}

# Pod Identity association: binds the role to the `external-secrets` controller SA. ESO's
# ClusterSecretStores authenticate as this controller identity (no per-store serviceAccountRef).
resource "aws_eks_pod_identity_association" "external_secrets" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "external-secrets"
  role_arn        = aws_iam_role.external_secrets[0].arn
  tags            = var.tags
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

  # The association must exist before the SA/pod rolls so the new pod gets Pod-Identity creds immediately.
  depends_on = [aws_eks_pod_identity_association.external_secrets]
}
