locals {
  create            = var.create
  enable_cloud_cost = local.create && var.enable_cloud_cost

  # On a spoke (no in-cluster queryable Prometheus) point OpenCost at an EXTERNAL Prometheus-compatible
  # endpoint — the hub Mimir's query API via its external ingress (which injects the tenant by hostname).
  # The dashboard uses OpenCost's EXPORTER metrics (computed from the k8s API + AWS pricing), so the
  # allocation-API query path is secondary — exporter metrics flow even if the query is degraded.
  use_external_prometheus = var.prometheus_external_url != ""

  opencost_prometheus = local.use_external_prometheus ? {
    external = {
      enabled = true
      url     = var.prometheus_external_url
    }
    internal = { enabled = false }
    } : {
    internal = {
      enabled       = true
      serviceName   = var.prometheus_service
      namespaceName = var.prometheus_namespace
      port          = var.prometheus_port
    }
  }

  # cloud-integration.json (#668 Phase 2a). No static keys: AWSServiceAccount uses the default AWS SDK
  # credential chain (Pod Identity), wrapped in AWSAssumeRole to cross into the mgmt-account cost_reader
  # role. NOTE: OpenCost's cloudCost pipeline is NOT Prometheus-scrapeable (only its own /cloudCost REST
  # API) — this wiring feeds OpenCost's own UI/API only. Grafana visibility is the separate
  # true-cost-exporter below, which queries Athena directly.
  cloud_integration = {
    aws = [{
      bucket    = var.cur_athena_results_bucket
      region    = var.cur_athena_region
      database  = var.cur_athena_database
      table     = var.cur_athena_table
      workgroup = var.cur_athena_workgroup
      account   = var.cur_account_id
      authorizer = {
        type    = "AWSAssumeRole"
        roleARN = var.cost_reader_role_arn
        authorizer = {
          type = "AWSServiceAccount"
        }
      }
    }]
  }

  helm_values = {
    # No bundled Prometheus — we point OpenCost at the existing kube-prometheus-stack Prometheus.
    prometheus = {
      internal = { enabled = false }
      external = { enabled = false }
    }

    opencost = {
      # OpenCost queries this Prometheus for node/pod resource usage → cost allocation (in-cluster on the
      # hub; external = the hub Mimir for a spoke).
      prometheus = local.opencost_prometheus
      # Scrape OpenCost's own cost metrics back into Prometheus (serviceMonitorSelectorNilUsesHelmValues=false
      # on the platform Prometheus → all ServiceMonitors are scraped).
      metrics = {
        serviceMonitor = { enabled = true }
      }
      exporter = {
        resources = {
          requests = { cpu = "10m", memory = "55Mi" }
          limits   = { memory = "256Mi" }
        }
      }
      # Node pricing (in-cluster allocation) uses the public AWS pricing API — no creds needed for that.
      # cloudCost (CUR/Athena, #668) is opt-in and cross-account; see cloud_integration above.
      cloudCost            = { enabled = local.enable_cloud_cost }
      cloudIntegrationJSON = local.enable_cloud_cost ? jsonencode(local.cloud_integration) : ""
    }
  }
}

resource "helm_release" "opencost" {
  count = local.create ? 1 : 0

  name       = "opencost"
  repository = var.helm_repository
  chart      = var.helm_chart
  version    = var.helm_chart_version
  namespace  = var.namespace

  timeout = var.helm_timeout
  wait    = true
  atomic  = true

  values = [yamlencode(local.helm_values)]
}

# ---------------------------------------------------------------------------
# Cost dashboard (ADR-091 Phase A) — provisioned as code via the Grafana sidecar (label
# grafana_dashboard=1). Per-team / per-environment compute cost from the OpenCost allocation × node
# hourly-cost metrics this module scrapes; team is derived from the environment-namespace prefix. The
# datasource placeholder is filled with the Mimir uid (where these metrics land).
# ---------------------------------------------------------------------------

resource "kubernetes_config_map_v1" "cost_dashboard" {
  count = local.create && var.create_dashboard ? 1 : 0

  metadata {
    name      = "cost-dashboard-by-team"
    namespace = var.namespace
    # k8s LABEL values (not the AWS tags — those allow spaces/arbitrary values that k8s rejects).
    labels = {
      grafana_dashboard              = "1"
      "app.kubernetes.io/part-of"    = "observability"
      "app.kubernetes.io/managed-by" = "terraform"
    }
    annotations = { grafana_folder = "Cost" }
  }

  data = {
    "team-cost.json" = replace(
      file("${path.module}/dashboards/team-cost.json"),
      "__COST_DS_UID__", var.dashboard_datasource_uid
    )
  }
}

# ---------------------------------------------------------------------------
# Cross-account Athena/Glue/S3 read (#668 Phase 2a/3) — Pod Identity (ADR-047), no static keys. Shared by
# OpenCost's own cloudCost pipeline and the true-cost-exporter (both assume the same mgmt cost_reader role;
# the mgmt-side trust (aws/cost-export module) is already scoped to the whole platform account, so this
# role is the actual least-privilege boundary on this side).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "cost_reader_assumer_trust" {
  count = local.enable_cloud_cost ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "cost_reader_assumer" {
  count = local.enable_cloud_cost ? 1 : 0

  name_prefix        = "${var.cluster_name}-cost-ro-"
  assume_role_policy = data.aws_iam_policy_document.cost_reader_assumer_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "cost_reader_assumer" {
  count = local.enable_cloud_cost ? 1 : 0

  name = "assume-mgmt-cost-reader"
  role = aws_iam_role.cost_reader_assumer[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeMgmtCostReader"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = [var.cost_reader_role_arn]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "opencost_cost_reader" {
  count = local.enable_cloud_cost ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "opencost" # chart's serviceAccountName defaults to the release name
  role_arn        = aws_iam_role.cost_reader_assumer[0].arn
  tags            = var.tags
}

resource "aws_eks_pod_identity_association" "true_cost_exporter" {
  count = local.enable_cloud_cost ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "true-cost-exporter"
  role_arn        = aws_iam_role.cost_reader_assumer[0].arn
  tags            = var.tags
}
