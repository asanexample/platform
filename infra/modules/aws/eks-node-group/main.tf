locals {
  create = var.create && length(var.node_groups) > 0
}

# ---------------------------------------------------------------------------
# IAM — Node Role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "node" {
  count = local.create ? 1 : 0

  name_prefix = "${var.cluster_name}-node-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "ec2.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "node_worker" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSWorkerNodePolicy"
}

resource "aws_iam_role_policy_attachment" "node_ecr" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEC2ContainerRegistryReadOnly"
}

resource "aws_iam_role_policy_attachment" "node_ssm" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
}

# Attached even with Cilium BYOCNI: required for EKS node registration
resource "aws_iam_role_policy_attachment" "node_cni" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.node[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKS_CNI_Policy"
}

# ---------------------------------------------------------------------------
# Launch Template — IMDS hardening
# ---------------------------------------------------------------------------

# A minimal launch template (no image_id, so EKS still injects the optimized AMI
# and bootstrap) that enforces IMDSv2 and a hop limit of 1. The hop limit stops
# pods from reaching the instance metadata endpoint and stealing the node IAM
# role's credentials; pods get their own credentials via IRSA.
resource "aws_launch_template" "this" {
  for_each = var.create ? var.node_groups : {}

  name_prefix = "${var.cluster_name}-${each.key}-"

  # EKS's auto-generated launch template encrypts the root volume. Our custom
  # template must do the same, or the DenyUnencryptedEbsOnLaunch SCP blocks node
  # launch ("not authorized to launch instances with this launch template").
  block_device_mappings {
    device_name = "/dev/xvda" # root device for the AL2023 EKS-optimized AMI
    ebs {
      encrypted   = true
      volume_size = 20
      volume_type = "gp3"
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
    instance_metadata_tags      = "disabled"
  }

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

# ---------------------------------------------------------------------------
# Managed Node Groups
# ---------------------------------------------------------------------------

resource "aws_eks_node_group" "this" {
  for_each = var.create ? var.node_groups : {}

  cluster_name    = var.cluster_name
  node_group_name = each.key
  node_role_arn   = aws_iam_role.node[0].arn
  subnet_ids      = each.value.subnet_ids
  instance_types  = each.value.instance_types
  capacity_type   = each.value.capacity_type
  ami_type        = each.value.ami_type

  launch_template {
    id      = aws_launch_template.this[each.key].id
    version = aws_launch_template.this[each.key].latest_version
  }

  scaling_config {
    desired_size = each.value.desired_size
    max_size     = each.value.max_size
    min_size     = each.value.min_size
  }

  update_config {
    max_unavailable = each.value.max_unavailable
  }

  labels = each.value.labels

  tags = merge(var.tags, { Name = "${var.cluster_name}-${each.key}" })

  depends_on = [
    aws_iam_role_policy_attachment.node_worker,
    aws_iam_role_policy_attachment.node_ecr,
    aws_iam_role_policy_attachment.node_ssm,
    aws_iam_role_policy_attachment.node_cni,
  ]
}
