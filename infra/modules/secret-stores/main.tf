locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# ClusterSecretStore — AWS Secrets Manager (EKS Pod Identity auth)
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
          # No `auth` block: ESO authenticates as the controller pod's own identity — the external-secrets
          # SA bound to its IAM role via EKS Pod Identity (ADR-047, #594). Replaces the IRSA jwt.serviceAccountRef.
        }
      }
    }
  }
}

# ---------------------------------------------------------------------------
# ClusterSecretStore — AWS SSM Parameter Store (EKS Pod Identity auth)
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
          # No `auth` block: ESO authenticates as the controller pod's own identity (EKS Pod Identity,
          # ADR-047, #594). Replaces the IRSA jwt.serviceAccountRef.
        }
      }
    }
  }
}
