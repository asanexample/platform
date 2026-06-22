locals {
  create  = var.create
  sa_name = "cloudwatch-exporter"

  # Sanitize tags for K8s label compliance (RFC-1123), mirroring the other observability modules.
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  # YACE scrape config — the platform's always-on AWS network resources (5-minute-period metrics).
  # Discovery is tag-based (tag:GetResources); resource tags are exported as Prometheus labels.
  # S3/storage daily metrics are intentionally omitted (different period; little operational value here).
  yace_config = {
    apiVersion   = "v1alpha1"
    "sts-region" = var.aws_region
    discovery = {
      exportedTagsOnMetrics = {
        "AWS/NetworkELB" = ["Name"]
      }
      jobs = [
        {
          type    = "AWS/NetworkELB"
          regions = var.scrape_regions
          period  = 300
          length  = 300
          metrics = [
            { name = "HealthyHostCount", statistics = ["Average", "Minimum"] },
            { name = "UnHealthyHostCount", statistics = ["Average", "Maximum"] },
            { name = "ActiveFlowCount", statistics = ["Average"] },
            { name = "ProcessedBytes", statistics = ["Sum"] },
            { name = "TCP_Target_Reset_Count", statistics = ["Sum"] },
          ]
        },
        {
          type    = "AWS/NATGateway"
          regions = var.scrape_regions
          period  = 300
          length  = 300
          metrics = [
            { name = "ErrorPortAllocation", statistics = ["Sum"] },
            { name = "PacketsDropCount", statistics = ["Sum"] },
            { name = "BytesOutToDestination", statistics = ["Sum"] },
          ]
        },
        {
          type    = "AWS/TransitGateway"
          regions = var.scrape_regions
          period  = 300
          length  = 300
          metrics = [
            { name = "BytesIn", statistics = ["Sum"] },
            { name = "BytesOut", statistics = ["Sum"] },
            { name = "PacketDropCountBlackhole", statistics = ["Sum"] },
          ]
        },
      ]
    }
  }

  helm_values = {
    nameOverride     = "cloudwatch-exporter"
    fullnameOverride = "cloudwatch-exporter"

    serviceAccount = {
      create = true
      name   = local.sa_name
      # Pod Identity (ADR-047) supplies AWS creds — no IRSA role-arn annotation.
    }

    # Scraped by the kube-prometheus-stack Prometheus (serviceMonitorSelectorNilUsesHelmValues=false → all SMs).
    serviceMonitor = {
      enabled  = true
      interval = "5m"
    }

    resources = {
      requests = { cpu = "20m", memory = "64Mi" }
      limits   = { memory = "128Mi" }
    }

    config = yamlencode(local.yace_config)
  }
}

# ---------------------------------------------------------------------------
# IAM — CloudWatch read for YACE via EKS Pod Identity (ADR-047; trust pods.eks.amazonaws.com, no IRSA).
# GetMetricData/ListMetrics don't support resource scoping, so Resource = "*" (read-only).
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "trust" {
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

resource "aws_iam_role" "this" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-cw-exp-"
  assume_role_policy = data.aws_iam_policy_document.trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "cloudwatch_read" {
  count = local.create ? 1 : 0

  name = "cloudwatch-read"
  role = aws_iam_role.this[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchAndDiscovery"
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:ListMetrics",
          "ec2:DescribeTransitGatewayAttachments",
          "ec2:DescribeRegions",
          "iam:ListAccountAliases", # YACE labels metrics with the account alias (else a per-scrape WARN)
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "this" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.sa_name
  role_arn        = aws_iam_role.this[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Helm release — prometheus-community/yet-another-cloudwatch-exporter
# ---------------------------------------------------------------------------
resource "helm_release" "yace" {
  count = local.create ? 1 : 0

  name       = "cloudwatch-exporter"
  repository = var.helm_repository
  chart      = var.helm_chart
  version    = var.helm_chart_version
  namespace  = var.namespace

  timeout = var.helm_timeout
  wait    = true
  atomic  = true

  values = [yamlencode(local.helm_values)]

  depends_on = [aws_eks_pod_identity_association.this]
}
