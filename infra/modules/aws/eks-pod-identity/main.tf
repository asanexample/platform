# ---------------------------------------------------------------------------
# EKS Pod Identity associations
# ---------------------------------------------------------------------------
# Binds (cluster, namespace, serviceAccount) -> IAM role. The association is the *only* thing that grants
# a pod its role — there is no SA annotation. Tenants cannot create associations (it is an AWS API call),
# so this is the platform-controlled, namespace+SA-scoped isolation boundary. See ADR-041.

resource "aws_eks_pod_identity_association" "this" {
  for_each = var.create ? var.associations : {}

  cluster_name    = var.cluster_name
  namespace       = each.value.namespace
  service_account = each.value.service_account
  role_arn        = each.value.role_arn

  tags = var.tags
}
