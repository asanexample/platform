locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# ClusterSecretStore — AWS Secrets Manager (IRSA auth)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "cluster_secret_store" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = var.store_name
    }
    spec = {
      provider = {
        aws = {
          service = "SecretsManager"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = var.service_account_name
                namespace = var.service_account_namespace
              }
            }
          }
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# ClusterSecretStore — AWS SSM Parameter Store (IRSA auth)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "cluster_secret_store_ssm" {
  count = local.create && var.create_ssm_store ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ClusterSecretStore"
    metadata = {
      name = "${var.store_name}-ssm"
    }
    spec = {
      provider = {
        aws = {
          service = "ParameterStore"
          region  = var.region
          auth = {
            jwt = {
              serviceAccountRef = {
                name      = var.service_account_name
                namespace = var.service_account_namespace
              }
            }
          }
        }
      }
    }
  }
}
