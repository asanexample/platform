locals {
  create      = var.create
  create_irsa = local.create && var.alerts_topic_arn != "" && var.oidc_provider_arn != ""

  # Sanitize tags for K8s label compliance (RFC-1123), mirroring the policy module.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # Deterministic names (release pinned so these are stable).
  grafana_service       = "${var.helm_release_name}-grafana"
  alertmanager_sa       = "${var.helm_release_name}-alertmanager"
  grafana_admin_secret  = "grafana-admin"
  grafana_admin_sm_name = "${var.secret_path_prefix}/observability/grafana-admin"
  prometheus_storage_spec = var.use_persistent_storage ? {
    volumeClaimTemplate = {
      spec = {
        storageClassName = var.storage_class
        accessModes      = ["ReadWriteOnce"]
        resources        = { requests = { storage = "20Gi" } }
      }
    }
  } : null

  # Alertmanager routing: critical → SNS, Watchdog → null (external heartbeat is a P4 follow-up),
  # everything else → null. Only wired when an SNS topic + IRSA are present.
  alertmanager_config = {
    global = { resolve_timeout = "5m" }
    route = {
      group_by        = ["namespace", "alertname"]
      group_wait      = "30s"
      group_interval  = "5m"
      repeat_interval = "4h"
      receiver        = "null"
      routes = concat(
        [{ receiver = "null", matchers = ["alertname = \"Watchdog\""] }],
        local.create_irsa ? [{ receiver = "critical-sns", matchers = ["severity = \"critical\""], continue = false }] : [],
      )
    }
    receivers = concat(
      [{ name = "null" }],
      local.create_irsa ? [{
        name = "critical-sns"
        sns_configs = [{
          topic_arn     = var.alerts_topic_arn
          sigv4         = { region = var.aws_region }
          subject       = "[{{ .CommonLabels.severity }}] {{ .CommonLabels.alertname }}"
          message       = "{{ range .Alerts }}{{ .Annotations.description }}{{ \"\\n\" }}{{ end }}"
          send_resolved = true
        }]
      }] : [],
    )
  }

  helm_values = {
    # --- EKS accuracy: managed control plane is unscrapeable; Cilium replaces kube-proxy. ---
    # Disable the scrape jobs AND their alert rule groups so we don't ship empty dashboards
    # or perpetually-firing "target down" alerts.
    kubeScheduler         = { enabled = false }
    kubeControllerManager = { enabled = false }
    kubeEtcd              = { enabled = false }
    kubeProxy             = { enabled = false }

    defaultRules = {
      create = true
      rules = {
        etcd                  = false
        kubeScheduler         = false
        kubeControllerManager = false
        kubeProxy             = false
      }
    }

    # --- Prometheus ---
    prometheus = {
      prometheusSpec = {
        replicas  = var.high_availability ? 2 : 1
        retention = var.prometheus_retention
        # Pick up ServiceMonitors / PodMonitors / Rules cluster-wide, not just chart-labelled ones
        # (so the per-component ServiceMonitors below — and future ones — are scraped).
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false
        probeSelectorNilUsesHelmValues          = false
        resources = {
          requests = { cpu = "200m", memory = "1Gi" }
          limits   = { memory = "2Gi" }
        }
        storageSpec     = local.prometheus_storage_spec
        podAntiAffinity = var.high_availability ? "hard" : "soft"
      }
      # Per-component ServiceMonitors for the tier-2 dashboards (sources that already expose metrics).
      # ArgoCD / Cilium-agent / External-Secrets need a metrics flag in their own unit first — added as
      # those units enable metrics (follow-up).
      additionalServiceMonitors = [
        {
          name              = "kyverno"
          namespaceSelector = { matchNames = ["kyverno"] }
          selector          = { matchLabels = { "app.kubernetes.io/part-of" = "kyverno" } }
          endpoints         = [{ port = "metrics-port", interval = "30s" }]
        },
        {
          name              = "cert-manager"
          namespaceSelector = { matchNames = ["cert-manager"] }
          selector          = { matchLabels = { "app.kubernetes.io/name" = "cert-manager" } }
          endpoints         = [{ port = "tcp-prometheus-servicemonitor", interval = "30s" }]
        },
      ]
    }

    # --- Alertmanager ---
    alertmanager = {
      alertmanagerSpec = {
        replicas        = var.high_availability ? 3 : 1
        podAntiAffinity = var.high_availability ? "hard" : "soft"
        resources = {
          requests = { cpu = "50m", memory = "128Mi" }
          limits   = { memory = "256Mi" }
        }
      }
      serviceAccount = {
        annotations = local.create_irsa ? {
          "eks.amazonaws.com/role-arn" = aws_iam_role.alertmanager[0].arn
        } : {}
      }
      config = local.alertmanager_config
    }

    # --- Grafana (hardened; admin via the TF-managed secret; SSO is a fast-follow) ---
    grafana = {
      replicas = var.high_availability ? 2 : 1
      admin = {
        existingSecret = local.grafana_admin_secret
        userKey        = "admin-user"
        passwordKey    = "admin-password"
      }
      defaultDashboardsEnabled  = true # tier-1 bundled dashboards
      defaultDashboardsTimezone = "utc"
      sidecar = {
        dashboards  = { enabled = true, label = "grafana_dashboard", searchNamespace = var.namespace, folderAnnotation = "grafana_folder", provider = { foldersFromFilesStructure = true } }
        datasources = { enabled = true }
      }
      service = { port = 80 }
      "grafana.ini" = {
        server           = { root_url = "https://${var.grafana_hostname}", enforce_domain = false }
        "auth.anonymous" = { enabled = false }
        users            = { viewers_can_edit = false, allow_sign_up = false, allow_org_create = false, default_theme = "dark" }
        security         = { cookie_secure = true, cookie_samesite = "strict", content_security_policy = true, disable_gravatar = true }
        plugins          = { allow_loading_unsigned_plugins = "" }
        analytics        = { reporting_enabled = false, check_for_updates = false }
      }
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }

    # node-exporter needs host access — the ns is created (below) with PSA `privileged` for it.
    "kube-state-metrics" = {}
    nodeExporter         = { enabled = true }
  }
}

# ---------------------------------------------------------------------------
# Namespace (PSA `privileged` for node-exporter; created here, NOT by the chart,
# so the label is set — and intentionally NO tenant label).
# ---------------------------------------------------------------------------
resource "kubernetes_namespace" "this" {
  count = local.create ? 1 : 0

  metadata {
    name = var.namespace
    labels = merge(local.k8s_labels, {
      "pod-security.kubernetes.io/enforce" = "privileged"
      "app.kubernetes.io/managed-by"       = "terraform"
    })
  }
}

# ---------------------------------------------------------------------------
# Network policies — default-deny ingress; allow intra-namespace; Grafana reachable
# (gateway path). Egress left open (Prometheus scrapes cluster-wide). Full store-endpoint
# isolation lands with the multi-tenant stores in P2.
# ---------------------------------------------------------------------------
resource "kubernetes_network_policy" "default_deny_ingress" {
  count = local.create ? 1 : 0

  metadata {
    name      = "default-deny-ingress"
    namespace = kubernetes_namespace.this[0].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
  }
}

resource "kubernetes_network_policy" "allow_intra_namespace" {
  count = local.create ? 1 : 0

  metadata {
    name      = "allow-intra-namespace"
    namespace = kubernetes_namespace.this[0].metadata[0].name
  }
  spec {
    pod_selector {}
    policy_types = ["Ingress"]
    ingress {
      from {
        pod_selector {}
      }
    }
  }
}

# Grafana ingress from the Cilium Gateway. The gateway's Envoy connects with the reserved Cilium
# `ingress` identity (8), which a STANDARD k8s NetworkPolicy `from:` cannot match (it's not a
# namespace/pod) — so this must be a CiliumNetworkPolicy with `fromEntities: ["ingress"]`
# (the repo's documented Gateway gotcha — see CLAUDE.md "Cilium Gateway API"). Cilium unions this
# allow with the k8s default-deny above, so Grafana is reachable only via the gateway (+ intra-ns
# scraping via allow-intra-namespace).
resource "kubernetes_manifest" "allow_grafana_from_gateway" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "cilium.io/v2"
    kind       = "CiliumNetworkPolicy"
    metadata = {
      name      = "allow-grafana-from-gateway"
      namespace = kubernetes_namespace.this[0].metadata[0].name
    }
    spec = {
      endpointSelector = { matchLabels = { "app.kubernetes.io/name" = "grafana" } }
      ingress = [{
        fromEntities = ["ingress"]
        toPorts      = [{ ports = [{ port = "3000", protocol = "TCP" }] }]
      }]
    }
  }

  depends_on = [kubernetes_namespace.this]
}

# ---------------------------------------------------------------------------
# Grafana admin credential — TF-generated (so TF owns it), mirrored to Secrets
# Manager for human retrieval, and delivered to the cluster as a k8s Secret.
# (Direct, since the secret originates in TF — ESO is for externally-sourced secrets.)
# ---------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  count   = local.create ? 1 : 0
  length  = 24
  special = false # avoid shell/URL-escaping headaches in the admin password
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  count = local.create ? 1 : 0

  name        = local.grafana_admin_sm_name
  description = "Grafana admin credential (observability hub). Interim until SSO lands."
  tags        = var.tags
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  count = local.create ? 1 : 0

  secret_id = aws_secretsmanager_secret.grafana_admin[0].id
  secret_string = jsonencode({
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin[0].result
  })
}

resource "kubernetes_secret" "grafana_admin" {
  count = local.create ? 1 : 0

  metadata {
    name      = local.grafana_admin_secret
    namespace = kubernetes_namespace.this[0].metadata[0].name
    labels    = local.k8s_labels
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin[0].result
  }
  type = "Opaque"
}

# ---------------------------------------------------------------------------
# Curated dashboards-as-code — one ConfigMap per JSON in dashboards/, picked up by the
# Grafana sidecar (label grafana_dashboard=1). Tier-1 bundled dashboards ship with the chart;
# these are the tier-3 custom (Platform Health) + tier-2 vendored ones.
# ---------------------------------------------------------------------------
resource "kubernetes_config_map" "dashboards" {
  for_each = local.create ? fileset("${path.module}/dashboards", "*.json") : toset([])

  metadata {
    name        = "obs-dashboard-${trimsuffix(each.value, ".json")}"
    namespace   = kubernetes_namespace.this[0].metadata[0].name
    labels      = merge(local.k8s_labels, { grafana_dashboard = "1" })
    annotations = { grafana_folder = "Platform" }
  }
  data = {
    (each.value) = file("${path.module}/dashboards/${each.value}")
  }
}

# ---------------------------------------------------------------------------
# IRSA — Alertmanager → SNS publish (the only AWS access in P1)
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "alertmanager_trust" {
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
      values   = ["system:serviceaccount:${var.namespace}:${local.alertmanager_sa}"]
    }
  }
}

resource "aws_iam_role" "alertmanager" {
  count = local.create_irsa ? 1 : 0

  name_prefix        = "${var.cluster_name}-am-sns-"
  assume_role_policy = data.aws_iam_policy_document.alertmanager_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "alertmanager_sns" {
  count = local.create_irsa ? 1 : 0

  name = "sns-publish"
  role = aws_iam_role.alertmanager[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "PublishAlerts"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = [var.alerts_topic_arn]
      },
      {
        # The alerts topic is SSE-KMS encrypted (AWS-managed alias/aws/sns key),
        # so publishing requires data-key access. The managed key's ARN isn't
        # known here; scope to SNS via kms:ViaService so the grant is only usable
        # for SNS publishes in this region.
        Sid      = "EncryptAlerts"
        Effect   = "Allow"
        Action   = ["kms:GenerateDataKey*", "kms:Decrypt"]
        Resource = ["*"]
        Condition = {
          StringEquals = { "kms:ViaService" = "sns.${var.aws_region}.amazonaws.com" }
        }
      },
    ]
  })
}

# ---------------------------------------------------------------------------
# kube-prometheus-stack
# ---------------------------------------------------------------------------
resource "helm_release" "kube_prometheus_stack" {
  count = local.create ? 1 : 0

  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = kubernetes_namespace.this[0].metadata[0].name
  create_namespace = false # created above with the PSA label
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [
    yamlencode(local.helm_values),
  ]

  depends_on = [
    kubernetes_secret.grafana_admin,
    kubernetes_network_policy.default_deny_ingress,
    aws_iam_role_policy.alertmanager_sns,
  ]
}
