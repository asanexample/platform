locals {
  create      = var.create
  create_irsa = local.create && var.oidc_provider_arn != ""

  irsa_addons = {
    for k, v in var.addons : k => v.irsa
    if v.irsa != null && local.create_irsa
  }
}

# ---------------------------------------------------------------------------
# IRSA — per-addon IAM roles
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "addon_trust" {
  for_each = local.irsa_addons

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [var.oidc_provider_arn]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:sub"
      values   = ["system:serviceaccount:${each.value.service_account_namespace}:${each.value.service_account_name}"]
    }

    condition {
      test     = "StringEquals"
      variable = "${var.oidc_provider_url}:aud"
      values   = ["sts.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "addon" {
  for_each = local.irsa_addons

  name               = "${var.cluster_name}-addon-${each.key}"
  assume_role_policy = data.aws_iam_policy_document.addon_trust[each.key].json
  tags               = var.tags
}

# Flatten the per-addon policy_arns lists so each (addon, policy_arn) pair gets its own attachment
resource "aws_iam_role_policy_attachment" "addon" {
  for_each = {
    for item in flatten([
      for addon_key, irsa in local.irsa_addons : [
        for idx, arn in irsa.policy_arns : {
          key        = "${addon_key}-${idx}"
          addon_key  = addon_key
          policy_arn = arn
        }
      ]
    ]) : item.key => item
  }

  role       = aws_iam_role.addon[each.value.addon_key].name
  policy_arn = each.value.policy_arn
}

# ---------------------------------------------------------------------------
# EKS managed add-ons
# ---------------------------------------------------------------------------

resource "aws_eks_addon" "this" {
  for_each = local.create ? var.addons : {}

  cluster_name         = var.cluster_name
  addon_name           = each.key
  addon_version        = each.value.addon_version
  configuration_values = each.value.configuration_values
  # Prefer caller-supplied role ARN; fall back to auto-created IRSA role
  service_account_role_arn = try(coalesce(each.value.service_account_role_arn, try(aws_iam_role.addon[each.key].arn, null)), null)
  # OVERWRITE ensures addon updates succeed even if K8s resources were manually modified
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}

# ---------------------------------------------------------------------------
# Default StorageClass (gp3 via the EBS CSI driver)
# ---------------------------------------------------------------------------
# EKS ships only the deprecated in-tree gp2 SC (non-default). Provide a gp3
# StorageClass as the cluster default so workloads get dynamic, encrypted,
# expandable EBS volumes. WaitForFirstConsumer defers binding until a pod is
# scheduled (respects zone/topology). depends_on the EBS CSI addon so its
# provisioner exists before anything binds a claim.

resource "kubernetes_storage_class" "gp3" {
  count = local.create && var.create_default_storageclass ? 1 : 0

  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.aws.com"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = true

  parameters = {
    type      = "gp3"
    encrypted = "true"
  }

  depends_on = [aws_eks_addon.this]
}
