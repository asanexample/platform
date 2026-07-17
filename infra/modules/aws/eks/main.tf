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

  # BYOCNI mode: disables default VPC CNI and kube-proxy. Cilium provides both.
  bootstrap_self_managed_addons = false
  enabled_cluster_log_types     = var.enabled_cluster_log_types

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
    # Dual-mode auth: EKS access entries (preferred) + aws-auth configmap (backward compat)
    authentication_mode = "API_AND_CONFIG_MAP"
  }

  tags = merge(var.tags, { Name = var.cluster_name })

  depends_on = [
    aws_iam_role_policy_attachment.cluster_policy,
    aws_iam_role_policy_attachment.vpc_resource_controller,
  ]
}

# ---------------------------------------------------------------------------
# Additional private-API ingress — out-of-cluster access paths
# ---------------------------------------------------------------------------
# The EKS-managed cluster SG admits only its own members (nodes) on 443. An
# out-of-cluster caller whose forwarded traffic is SNAT'd into the VPC — e.g. a
# standalone Tailscale subnet router (ADR-010) — reaches the private API from a
# VPC IP that isn't in that SG, so open the API to its CIDR here. Default-empty,
# so this is a no-op until a unit opts in.
resource "aws_vpc_security_group_ingress_rule" "api_additional_cidr" {
  for_each = local.create ? toset(var.additional_api_ingress_cidrs) : toset([])

  security_group_id = aws_eks_cluster.this[0].vpc_config[0].cluster_security_group_id
  description       = "HTTPS to private API from ${each.value}"
  ip_protocol       = "tcp"
  from_port         = 443
  to_port           = 443
  cidr_ipv4         = each.value

  tags = var.tags
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
  client_id_list  = ["sts.amazonaws.com"] # Required audience for IRSA token validation
  thumbprint_list = [data.tls_certificate.cluster[0].certificates[0].sha1_fingerprint]

  tags = merge(var.tags, { Name = "${var.cluster_name}-oidc" })
}

# ---------------------------------------------------------------------------
# Access Entries
# ---------------------------------------------------------------------------

resource "aws_eks_access_entry" "this" {
  for_each = local.create ? var.access_entries : {}

  cluster_name      = aws_eks_cluster.this[0].name
  principal_arn     = each.value.principal_arn
  type              = each.value.type
  kubernetes_groups = each.value.kubernetes_groups
}

# Only entries with an AWS-managed policy_arn get an access policy association.
# Entries that instead map to kubernetes_groups rely on cluster-managed RBAC.
resource "aws_eks_access_policy_association" "this" {
  for_each = local.create ? { for k, v in var.access_entries : k => v if v.policy_arn != null } : {}

  cluster_name  = aws_eks_cluster.this[0].name
  principal_arn = each.value.principal_arn
  policy_arn    = each.value.policy_arn

  access_scope {
    type       = each.value.scope_type
    namespaces = each.value.namespaces
  }

  depends_on = [aws_eks_access_entry.this]
}

# ---------------------------------------------------------------------------
# EKS Managed Add-ons
# ---------------------------------------------------------------------------

# Addons at cluster creation time (before CNI/nodes). For post-CNI addons, use eks-addons module.
resource "aws_eks_addon" "this" {
  for_each = local.create ? var.eks_addons : {}

  cluster_name                = aws_eks_cluster.this[0].name
  addon_name                  = each.key
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}
