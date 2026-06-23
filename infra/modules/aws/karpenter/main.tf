data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}

locals {
  create = var.create

  name      = "Karpenter-${var.cluster_name}"
  queue_arn = try(aws_sqs_queue.interruption[0].arn, "")

  # Karpenter nodes assume the SAME node role the managed groups use; the EC2NodeClass wants its NAME.
  node_role_name = var.node_role_arn != "" ? element(split("/", var.node_role_arn), 1) : ""

  # Single-AZ (dev) pins to the first subnet — mirrors the eks-node-group module's slice.
  selected_subnets = var.single_az ? slice(sort(var.subnet_ids), 0, 1) : var.subnet_ids

  _default_families = var.node_arch == "arm64" ? ["t4g", "m6g", "m7g", "c6g", "r6g"] : ["t3", "t3a", "m5", "m6i", "c6i", "r6i"]
  instance_families = length(var.instance_families) > 0 ? var.instance_families : local._default_families

  # K8s arch label value (Karpenter NodePool requirement). node_arch arm64 -> arm64, else amd64.
  k8s_arch = var.node_arch == "arm64" ? "arm64" : "amd64"

  account     = data.aws_caller_identity.current.account_id
  partition   = data.aws_partition.current.partition
  cluster_tag = "kubernetes.io/cluster/${var.cluster_name}"
}

# ---------------------------------------------------------------------------
# Controller IAM — EKS Pod Identity (ADR-047; trust pods.eks.amazonaws.com, no IRSA).
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "controller_trust" {
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

resource "aws_iam_role" "controller" {
  count = local.create ? 1 : 0

  name_prefix        = "${var.cluster_name}-karpenter-"
  assume_role_policy = data.aws_iam_policy_document.controller_trust[0].json
  tags               = var.tags
}

# Standard Karpenter v1 controller policy, scoped to this cluster via tag conditions.
resource "aws_iam_role_policy" "controller" {
  count = local.create ? 1 : 0

  name = "karpenter-controller"
  role = aws_iam_role.controller[0].id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowScopedEC2InstanceAccessActions"
        Effect = "Allow"
        Action = ["ec2:RunInstances", "ec2:CreateFleet"]
        Resource = [
          "arn:${local.partition}:ec2:${var.aws_region}::image/*",
          "arn:${local.partition}:ec2:${var.aws_region}::snapshot/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:security-group/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:subnet/*",
        ]
      },
      {
        Sid      = "AllowScopedEC2LaunchTemplateAccessActions"
        Effect   = "Allow"
        Action   = ["ec2:RunInstances", "ec2:CreateFleet"]
        Resource = "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*"
        Condition = {
          StringEquals = { "aws:ResourceTag/${local.cluster_tag}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedEC2InstanceActionsWithTags"
        Effect = "Allow"
        Action = ["ec2:RunInstances", "ec2:CreateFleet", "ec2:CreateLaunchTemplate"]
        Resource = [
          "arn:${local.partition}:ec2:${var.aws_region}:*:fleet/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:volume/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:network-interface/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
        ]
        Condition = {
          StringEquals = { "aws:RequestTag/${local.cluster_tag}" = "owned" }
          StringLike   = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedResourceCreationTagging"
        Effect = "Allow"
        Action = ["ec2:CreateTags"]
        Resource = [
          "arn:${local.partition}:ec2:${var.aws_region}:*:fleet/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:volume/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:network-interface/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:spot-instances-request/*",
        ]
        Condition = {
          StringEquals = {
            "aws:RequestTag/${local.cluster_tag}" = "owned"
            "ec2:CreateAction"                    = ["RunInstances", "CreateFleet", "CreateLaunchTemplate"]
          }
          StringLike = { "aws:RequestTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid    = "AllowScopedDeletion"
        Effect = "Allow"
        Action = ["ec2:TerminateInstances", "ec2:DeleteLaunchTemplate"]
        Resource = [
          "arn:${local.partition}:ec2:${var.aws_region}:*:instance/*",
          "arn:${local.partition}:ec2:${var.aws_region}:*:launch-template/*",
        ]
        Condition = {
          StringEquals = { "aws:ResourceTag/${local.cluster_tag}" = "owned" }
          StringLike   = { "aws:ResourceTag/karpenter.sh/nodepool" = "*" }
        }
      },
      {
        Sid      = "AllowRegionalReadActions"
        Effect   = "Allow"
        Resource = "*"
        Action = [
          "ec2:DescribeImages", "ec2:DescribeInstances", "ec2:DescribeInstanceTypeOfferings",
          "ec2:DescribeInstanceTypes", "ec2:DescribeLaunchTemplates", "ec2:DescribeSecurityGroups",
          "ec2:DescribeSpotPriceHistory", "ec2:DescribeSubnets", "ec2:DescribeAvailabilityZones",
        ]
        Condition = { StringEquals = { "aws:RequestedRegion" = var.aws_region } }
      },
      {
        Sid      = "AllowSSMReadActions"
        Effect   = "Allow"
        Action   = ["ssm:GetParameter"]
        Resource = "arn:${local.partition}:ssm:${var.aws_region}::parameter/aws/service/*"
      },
      {
        Sid      = "AllowPricingReadActions"
        Effect   = "Allow"
        Action   = ["pricing:GetProducts"]
        Resource = "*"
      },
      {
        Sid      = "AllowInterruptionQueueActions"
        Effect   = "Allow"
        Action   = ["sqs:DeleteMessage", "sqs:GetQueueUrl", "sqs:ReceiveMessage"]
        Resource = local.queue_arn
      },
      {
        Sid       = "AllowPassingInstanceRole"
        Effect    = "Allow"
        Action    = ["iam:PassRole"]
        Resource  = var.node_role_arn
        Condition = { StringEquals = { "iam:PassedToService" = "ec2.amazonaws.com" } }
      },
      {
        Sid      = "AllowScopedInstanceProfileCreationActions"
        Effect   = "Allow"
        Action   = ["iam:CreateInstanceProfile"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestTag/${local.cluster_tag}"          = "owned"
            "aws:RequestTag/topology.kubernetes.io/region" = var.aws_region
          }
          StringLike = { "aws:RequestTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileTagActions"
        Effect   = "Allow"
        Action   = ["iam:TagInstanceProfile"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/${local.cluster_tag}"          = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region" = var.aws_region
            "aws:RequestTag/${local.cluster_tag}"           = "owned"
            "aws:RequestTag/topology.kubernetes.io/region"  = var.aws_region
          }
          StringLike = { "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "AllowScopedInstanceProfileActions"
        Effect   = "Allow"
        Action   = ["iam:AddRoleToInstanceProfile", "iam:RemoveRoleFromInstanceProfile", "iam:DeleteInstanceProfile"]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:ResourceTag/${local.cluster_tag}"          = "owned"
            "aws:ResourceTag/topology.kubernetes.io/region" = var.aws_region
          }
          StringLike = { "aws:ResourceTag/karpenter.k8s.aws/ec2nodeclass" = "*" }
        }
      },
      {
        Sid      = "AllowInstanceProfileReadActions"
        Effect   = "Allow"
        Action   = ["iam:GetInstanceProfile", "iam:ListInstanceProfiles"]
        Resource = "*"
      },
      {
        Sid      = "AllowAPIServerEndpointDiscovery"
        Effect   = "Allow"
        Action   = ["eks:DescribeCluster"]
        Resource = "arn:${local.partition}:eks:${var.aws_region}:${local.account}:cluster/${var.cluster_name}"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "controller" {
  count = local.create ? 1 : 0

  cluster_name    = var.cluster_name
  namespace       = var.namespace
  service_account = "karpenter"
  role_arn        = aws_iam_role.controller[0].arn
  tags            = var.tags
}

# ---------------------------------------------------------------------------
# Spot/maintenance interruption queue (D7) — EventBridge → SQS; Karpenter drains gracefully.
# ---------------------------------------------------------------------------

resource "aws_sqs_queue" "interruption" {
  count = local.create ? 1 : 0

  name                      = "${var.cluster_name}-karpenter"
  message_retention_seconds = 300
  sqs_managed_sse_enabled   = true
  tags                      = var.tags
}

data "aws_iam_policy_document" "queue" {
  count = local.create ? 1 : 0

  statement {
    sid       = "EventBridgePublish"
    effect    = "Allow"
    actions   = ["sqs:SendMessage"]
    resources = [aws_sqs_queue.interruption[0].arn]
    principals {
      type        = "Service"
      identifiers = ["events.amazonaws.com", "sqs.amazonaws.com"]
    }
  }
}

resource "aws_sqs_queue_policy" "interruption" {
  count = local.create ? 1 : 0

  queue_url = aws_sqs_queue.interruption[0].url
  policy    = data.aws_iam_policy_document.queue[0].json
}

locals {
  event_rules = local.create ? {
    health_event      = { source = ["aws.health"], detail_type = ["AWS Health Event"] }
    spot_interruption = { source = ["aws.ec2"], detail_type = ["EC2 Spot Instance Interruption Warning"] }
    rebalance         = { source = ["aws.ec2"], detail_type = ["EC2 Instance Rebalance Recommendation"] }
    state_change      = { source = ["aws.ec2"], detail_type = ["EC2 Instance State-change Notification"] }
  } : {}
}

resource "aws_cloudwatch_event_rule" "this" {
  for_each = local.event_rules

  name_prefix   = "${substr(var.cluster_name, 0, 20)}-kpt-"
  event_pattern = jsonencode({ source = each.value.source, "detail-type" = each.value.detail_type })
  tags          = var.tags
}

resource "aws_cloudwatch_event_target" "this" {
  for_each = local.event_rules

  rule = aws_cloudwatch_event_rule.this[each.key].name
  arn  = aws_sqs_queue.interruption[0].arn
}

# ---------------------------------------------------------------------------
# Helm — CRDs first, then the controller.
# ---------------------------------------------------------------------------

resource "helm_release" "crd" {
  count = local.create ? 1 : 0

  name             = "karpenter-crd"
  repository       = var.helm_repository
  chart            = "karpenter-crd"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = true
}

resource "helm_release" "controller" {
  count = local.create ? 1 : 0

  name             = "karpenter"
  repository       = var.helm_repository
  chart            = "karpenter"
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true

  values = [yamlencode({
    replicas = var.high_availability ? 2 : 1
    serviceAccount = {
      create      = true
      name        = "karpenter"
      annotations = {} # Pod Identity (ADR-047) — NO IRSA annotation.
    }
    settings = {
      clusterName       = var.cluster_name
      interruptionQueue = aws_sqs_queue.interruption[0].name
    }
    # Run on the stable system node group — never on the nodes Karpenter manages (consolidation can't kill it).
    nodeSelector = { "node-role" = "system" }
    controller = {
      resources = {
        requests = { cpu = "100m", memory = "256Mi" }
        limits   = { memory = "512Mi" }
      }
    }
    serviceMonitor = { enabled = var.service_monitor_enabled }
  })]

  depends_on = [
    helm_release.crd,
    aws_iam_role_policy.controller,
    aws_eks_pod_identity_association.controller,
  ]
}

# ---------------------------------------------------------------------------
# EC2NodeClass + NodePool — via a local chart so the CRs don't need the CRD at plan time
# (the Sloth/Pyroscope pattern). depends_on the controller so the CRDs + webhook are up.
# ---------------------------------------------------------------------------

resource "helm_release" "nodepool" {
  count = local.create ? 1 : 0

  name             = "karpenter-nodepool"
  chart            = "${path.module}/charts/nodepool"
  namespace        = var.namespace
  create_namespace = false
  timeout          = var.helm_timeout
  wait             = false

  values = [yamlencode({
    clusterName         = var.cluster_name
    nodeRole            = local.node_role_name
    subnetIds           = local.selected_subnets
    securityGroupId     = var.cluster_security_group_id
    arch                = local.k8s_arch
    instanceFamilies    = local.instance_families
    capacityTypes       = var.capacity_types
    consolidationPolicy = var.consolidation_policy
    consolidateAfter    = var.consolidate_after
    cpuLimit            = var.cpu_limit
    memoryLimit         = var.memory_limit
    # BYOCNI: pods must not land before Cilium is ready; Cilium removes this taint (D5).
    startupTaintKey = "node.cilium.io/agent-not-ready"
    maxPods         = 110
    # Drop `Team` — the org `DenyTeamTagTampering` SCP forbids non-exempt roles (Karpenter included) from
    # setting it on ec2:CreateTags, and Karpenter's nodes are shared infra, not team-scoped resources. (The
    # alternative is exempting the Karpenter role in the SCP — an org/mgmt change; deliberately avoided here.)
    tags = { for k, v in var.tags : k => v if k != "Team" }
  })]

  depends_on = [helm_release.controller]
}
