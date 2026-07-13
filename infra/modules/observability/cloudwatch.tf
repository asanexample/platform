# ---------------------------------------------------------------------------
# P5a — Grafana CloudWatch read (Pod Identity; ADR-047 — trust pods.eks.amazonaws.com, no IRSA).
# Read-only CloudWatch + CloudWatch-Logs + tag/EC2 describe (the standard Grafana CloudWatch-datasource
# permission set; GetMetricData/ListMetrics don't support resource scoping, so Resource = "*").
# ---------------------------------------------------------------------------
data "aws_iam_policy_document" "grafana_cloudwatch_trust" {
  count = local.cloudwatch_enabled ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole", "sts:TagSession"]
    principals {
      type        = "Service"
      identifiers = ["pods.eks.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "grafana_cloudwatch" {
  count = local.cloudwatch_enabled ? 1 : 0

  name_prefix        = "${var.cluster_name}-graf-cw-"
  assume_role_policy = data.aws_iam_policy_document.grafana_cloudwatch_trust[0].json
  tags               = var.tags
}

resource "aws_iam_role_policy" "grafana_cloudwatch" {
  count = local.cloudwatch_enabled ? 1 : 0

  name = "cloudwatch-read"
  role = aws_iam_role.grafana_cloudwatch[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "CloudWatchRead"
        Effect = "Allow"
        Action = [
          "cloudwatch:DescribeAlarmsForMetric",
          "cloudwatch:DescribeAlarmHistory",
          "cloudwatch:DescribeAlarms",
          "cloudwatch:ListMetrics",
          "cloudwatch:GetMetricData",
          "cloudwatch:GetMetricStatistics",
          "cloudwatch:GetInsightRuleReport",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "CloudWatchLogsRead"
        Effect = "Allow"
        Action = [
          "logs:DescribeLogGroups",
          "logs:GetLogGroupFields",
          "logs:StartQuery",
          "logs:StopQuery",
          "logs:GetQueryResults",
          "logs:GetLogEvents",
        ]
        Resource = ["*"]
      },
      {
        Sid    = "ResourceTagAndEC2Describe"
        Effect = "Allow"
        Action = [
          "tag:GetResources",
          "ec2:DescribeTags",
          "ec2:DescribeInstances",
          "ec2:DescribeRegions",
        ]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "grafana_cloudwatch" {
  count = local.cloudwatch_enabled ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = local.grafana_service # chart names the SA <release>-grafana
  role_arn        = aws_iam_role.grafana_cloudwatch[0].arn
  tags            = var.tags
}
