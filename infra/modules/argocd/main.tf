locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""

  # Sanitize tags for K8s label compliance (RFC 1123): lowercase, valid chars, max 63 chars
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  irsa_annotations = local.create_irsa ? {
    "eks.amazonaws.com/role-arn" = aws_iam_role.argocd[0].arn
  } : {}

  # Per-component metrics: enabling creates the metrics Service AND a ServiceMonitor (the
  # Prometheus-operator CRD is present once the observability hub is installed, #102 P1).
  metrics = {
    enabled        = var.metrics_enabled
    serviceMonitor = { enabled = var.metrics_enabled }
  }

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
      metrics = local.metrics
    }

    server = {
      replicas = var.high_availability ? 2 : 1
      service = {
        type = var.server_service_type
      }
      serviceAccount = {
        annotations = local.irsa_annotations
      }
      metrics = local.metrics
    }

    repoServer = {
      replicas = var.high_availability ? 2 : 1
      serviceAccount = {
        annotations = local.irsa_annotations
      }
      metrics = local.metrics
    }

    applicationSet = {
      enabled  = var.applicationset_enabled
      replicas = var.high_availability ? 2 : 1
      metrics  = local.metrics
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

  role = aws_iam_role.argocd[0].name
  # Allows ArgoCD to pull Helm charts and container images from ECR
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "extra" {
  for_each = local.create_irsa ? toset(var.extra_iam_policy_arns) : toset([])

  role       = aws_iam_role.argocd[0].name
  policy_arn = each.value
}

# Allows ArgoCD to assume cross-account roles for managing remote EKS clusters
resource "aws_iam_role_policy" "remote_clusters" {
  count = local.create_irsa && length(var.remote_cluster_role_arns) > 0 ? 1 : 0

  name = "remote-cluster-access"
  role = aws_iam_role.argocd[0].name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = "sts:AssumeRole"
      Resource = var.remote_cluster_role_arns
    }]
  })
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
  atomic           = var.helm_wait # atomic requires wait=true; tied to same var so they stay consistent
  cleanup_on_fail  = true
  replace          = true # Delete and recreate the release on failed upgrade (avoids stuck FAILED state)

  values = [
    yamlencode(local.argocd_values),
  ]

  # Force Helm release upgrade when computed values change (Helm may miss yamlencode diffs)
  set = [
    {
      name  = "configHash"
      value = sha256(yamlencode(local.argocd_values))
    },
  ]

  depends_on = [aws_iam_role.argocd]
}

# ---------------------------------------------------------------------------
# OIDC client-secret ExternalSecret
# Syncs the OIDC client secret from Secrets Manager into a Secret labeled `app.kubernetes.io/part-of: argocd`
# (required, or ArgoCD won't resolve a `$<name>:<key>` reference in argocd-cm). mergePolicy=Merge keeps the
# fetched data key while adding the label. Depends on the Helm release so the namespace exists. ADR-053/059.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "oidc_external_secret" {
  count = local.create && var.oidc_external_secret_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = var.oidc_k8s_secret_name
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.oidc_secret_store_name, kind = "ClusterSecretStore" }
      target = {
        name           = var.oidc_k8s_secret_name
        creationPolicy = "Owner"
        template = {
          engineVersion = "v2"
          mergePolicy   = "Merge"
          metadata = {
            labels = { "app.kubernetes.io/part-of" = "argocd" }
          }
        }
      }
      data = [{
        secretKey = var.oidc_k8s_secret_key
        remoteRef = {
          key      = var.oidc_secret_manager_key
          property = var.oidc_secret_manager_property
        }
      }]
    }
  }

  depends_on = [helm_release.argocd]
}
