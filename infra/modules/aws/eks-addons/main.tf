resource "aws_eks_addon" "this" {
  for_each = var.create ? var.addons : {}

  cluster_name                = var.cluster_name
  addon_name                  = each.key
  addon_version               = each.value.addon_version
  configuration_values        = each.value.configuration_values
  resolve_conflicts_on_create = "OVERWRITE"
  resolve_conflicts_on_update = "OVERWRITE"

  tags = var.tags
}
