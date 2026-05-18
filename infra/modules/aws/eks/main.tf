locals {
  create     = var.create
  create_kms = local.create && var.enable_secrets_encryption
}

# ---------------------------------------------------------------------------
# IAM — Cluster Service Role
# ---------------------------------------------------------------------------

resource "aws_iam_role" "cluster" {
  count = local.create ? 1 : 0

  name_prefix = "${var.cluster_name}-cluster-"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "eks.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })

  tags = var.tags
}

resource "aws_iam_role_policy_attachment" "cluster_policy" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSClusterPolicy"
}

resource "aws_iam_role_policy_attachment" "vpc_resource_controller" {
  count = local.create ? 1 : 0

  role       = aws_iam_role.cluster[0].name
  policy_arn = "arn:aws:iam::aws:policy/AmazonEKSVPCResourceController"
}

# ---------------------------------------------------------------------------
# KMS — Envelope Encryption for Secrets
# ---------------------------------------------------------------------------

resource "aws_kms_key" "eks" {
  count = local.create_kms ? 1 : 0

  description         = "EKS secrets encryption for ${var.cluster_name}"
  enable_key_rotation = true

  tags = merge(var.tags, { Name = "${var.cluster_name}-eks" })
}

resource "aws_kms_alias" "eks" {
  count = local.create_kms ? 1 : 0

  name          = "alias/${var.cluster_name}-eks"
  target_key_id = aws_kms_key.eks[0].key_id
}

# ---------------------------------------------------------------------------
# EKS Cluster
# ---------------------------------------------------------------------------

resource "aws_eks_cluster" "this" {
  count = local.create ? 1 : 0

  name     = var.cluster_name
  role_arn = aws_iam_role.cluster[0].arn
  version  = var.kubernetes_version

  bootstrap_self_managed_addons = var.bootstrap_self_managed_addons

  vpc_config {
    subnet_ids              = var.subnet_ids
    endpoint_private_access = var.endpoint_private_access
    endpoint_public_access  = var.endpoint_public_access
    public_access_cidrs     = var.public_access_cidrs
    security_group_ids      = var.additional_security_group_ids
  }

  dynamic "encryption_config" {
    for_each = local.create_kms ? [1] : []
    content {
      provider {
        key_arn = aws_kms_key.eks[0].arn
      }
      resources = ["secrets"]
    }
  }

  access_config {
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = merge(var.tags, { Name = var.cluster_name })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.vpc_resource_controller,
  ]
}

# ---------------------------------------------------------------------------
# OIDC Provider (for IRSA)
# ---------------------------------------------------------------------------

data "tls_certificate" "cluster" {
  count = local.create ? 1 : 0

  url = aws_eks_cluster.this[0].identity[0].oidc[0].issuer
}

resource "aws_iam_openid_connect_provider" "cluster" {
  count = local.create ? 1 : 0

  url             = aws_eks_cluster.this[0].identity[0].oidc[0].issuer
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

# ---------------------------------------------------------------------------
# Access Entries
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "this" {
  for_each = local.create ? var.access_entries : {}

  cluster_name  = aws_eks_cluster.this[0].name
  principal_arn = each.value.principal_arn
  type          = each.value.type
}

resource "aws_eks_access_policy_association" "this" {
  for_each = local.create ? var.access_entries : {}

  cluster_name  = aws_eks_cluster.this[0].name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope_type
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.this]
}
