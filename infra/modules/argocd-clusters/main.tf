locals {
  create   = var.create
  clusters = local.create ? var.clusters : {}
}

resource "kubernetes_secret_v1" "cluster" {
  for_each = local.clusters

  metadata {
    name      = each.key
    namespace = var.namespace
    labels = {
      "argocd.argoproj.io/secret-type" = "cluster"
    }
  }

  data = {
    name   = each.key
    server = each.value.server
    config = jsonencode(merge(
      {
        tlsClientConfig = {
          caData = each.value.ca_data
        }
      },
      each.value.aws_auth != null ? {
        awsAuthConfig = {
          clusterName = each.value.aws_auth.cluster_name
          roleARN     = each.value.aws_auth.role_arn
        }
      } : {},
    ))
  }
}
