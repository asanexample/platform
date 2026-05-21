locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  irsa_annotations = local.create_irsa ? {
    "eks.amazonaws.com/role-arn" = aws_iam_role.argocd[0].arn
  } : {}

  argocd_values = {
    global = {
      podLabels = local.k8s_labels
    }

    configs = {
      params = {
        "server.insecure" = var.server_insecure
      }

      cm = merge(
        {
          "timeout.reconciliation" = var.reconciliation_timeout
          "resource.exclusions"    = yamlencode(var.resource_exclusions)
        },
        var.argocd_cm_extra,
      )

      rbac = merge(
        {
          "policy.default" = var.rbac_default_policy
          "policy.csv"     = var.rbac_policy_csv
        },
        var.rbac_scopes != "" ? { "scopes" = var.rbac_scopes } : {},
      )

      repositories        = var.repositories
      credentialTemplates = var.credential_templates
    }

    controller = {
      replicas = var.high_availability ? 2 : 1
      serviceAccount = {
        annotations = local.irsa_annotations
      }
    }

    server = {
      replicas = var.high_availability ? 2 : 1
      service = {
        type = var.server_service_type
      }
      serviceAccount = {
        annotations = local.irsa_annotations
      }
    }

    repoServer = {
      replicas = var.high_availability ? 2 : 1
      serviceAccount = {
        annotations = local.irsa_annotations
      }
    }

    applicationSet = {
      enabled  = var.applicationset_enabled
      replicas = var.high_availability ? 2 : 1
    }

    notifications = {
      enabled = var.notifications_enabled
    }

    dex = {
      enabled = var.dex_enabled
    }
  }
}

# ---------------------------------------------------------------------------
# IRSA — IAM Role for ArgoCD service accounts
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "argocd_trust" {
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
      values = [
        "system:serviceaccount:${var.namespace}:argocd-server",
        "system:serviceaccount:${var.namespace}:argocd-repo-server",
        "system:serviceaccount:${var.namespace}:argocd-application-controller",
      ]
    }
  }
}

resource "aws_iam_role" "argocd" {
  count = local.create_irsa ? 1 : 0

  name_prefix        = "${var.cluster_name}-argocd-"
  assume_role_policy = data.aws_iam_policy_document.argocd_trust[0].json

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "ecr_read" {
  count = local.create_irsa ? 1 : 0

  role       = aws_iam_role.argocd[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = local.create_irsa ? toset(var.extra_iam_policy_arns) : toset([])

  role       = aws_iam_role.argocd[0].name
  policy_arn = each.value
}

# ---------------------------------------------------------------------------
# Helm Release
# ---------------------------------------------------------------------------

resource "helm_release" "argocd" {
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
    yamlencode(local.argocd_values),
  ]

  set = [
    {
      name  = "configHash"
      value = sha256(yamlencode(local.argocd_values))
    },
  ]

  depends_on = [aws_iam_role.argocd]
}
