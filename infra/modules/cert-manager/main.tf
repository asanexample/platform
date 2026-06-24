locals {
  create = var.create

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  cert_manager_values = {
    installCRDs = true

    config = {
      enableGatewayAPI = true
    }

    global = {
      podLabels = local.k8s_labels
    }

    # AWS identity via EKS Pod Identity (ADR-047): the cert-manager SA is matched by the
    # pod-identity association below — no IRSA `eks.amazonaws.com/role-arn` annotation needed.

    securityContext = {
      fsGroup = 1001 # cert-manager runs as non-root uid 1001; fsGroup ensures volume mounts are writable
    }

    # EKS + Cilium overlay (cluster-pool): the EKS managed control plane can't route to overlay pod
    # IPs, so the webhook server runs on hostNetwork (node VPC IP the API server can dial). securePort
    # moves off 10250 (kubelet) to avoid a host-port clash; ClusterFirstWithHostNet keeps DNS working.
    webhook = {
      hostNetwork = var.webhook_host_network
      securePort  = var.webhook_host_network ? 10260 : 10250
    }
  }
}

# ---------------------------------------------------------------------------
# IAM — cert-manager role (DNS-01 via Route53); AWS identity via EKS Pod Identity (ADR-047)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "cert_manager_trust" {
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

resource "aws_iam_role" "cert_manager" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-cert-mgr-"
  assume_role_policy = data.aws_iam_policy_document.cert_manager_trust[0].json

  tags = var.tags
}

data "aws_iam_policy_document" "cert_manager_route53" {
  count = local.create ? 1 : 0

  statement {
    effect = "Allow"
    # GetChange polls for DNS propagation status after creating DNS-01 challenge TXT records
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
    # List actions don't support resource-level restrictions in Route53 IAM
    actions = [
      "route53:ListHostedZones",
      "route53:ListHostedZonesByName",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_role_policy" "cert_manager_route53" {
  count = local.create ? 1 : 0

  name   = "route53-dns01"
  role   = aws_iam_role.cert_manager[0].id
  policy = data.aws_iam_policy_document.cert_manager_route53[0].json
}

# Pod Identity association: binds the role to the `cert-manager` controller SA (the DNS-01 solver).
# The webhook/cainjector SAs need no AWS access, so only this SA is associated.
resource "aws_eks_pod_identity_association" "cert_manager" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "cert-manager"
  role_arn        = aws_iam_role.cert_manager[0].arn
  tags            = var.tags
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

  # The association must exist before the SA/pod rolls so the new pod gets Pod-Identity creds immediately.
  depends_on = [aws_eks_pod_identity_association.cert_manager]
}
