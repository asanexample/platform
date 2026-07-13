# ---------------------------------------------------------------------------
# Grafana admin credential — TF-generated (so TF owns it), mirrored to Secrets
# Manager for human retrieval, and delivered to the cluster as a k8s Secret.
# (Direct, since the secret originates in TF — ESO is for externally-sourced secrets.)
# ---------------------------------------------------------------------------
resource "random_password" "grafana_admin" {
  count   = local.create ? 1 : 0
  length  = 24
  special = false # avoid shell/URL-escaping headaches in the admin password
}

resource "aws_secretsmanager_secret" "grafana_admin" {
  count = local.create ? 1 : 0

  name        = local.grafana_admin_sm_name
  description = "Grafana admin credential (observability hub). Interim until SSO lands."
  # 0 = force-delete on destroy so a teardown→rebuild can recreate the same name; otherwise the default
  # 30-day recovery window leaves it "scheduled for deletion" and CreateSecret fails on the next bootstrap.
  recovery_window_in_days = var.secret_recovery_window_days
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "grafana_admin" {
  count = local.create ? 1 : 0

  secret_id = aws_secretsmanager_secret.grafana_admin[0].id
  secret_string = jsonencode({
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin[0].result
  })
}

resource "kubernetes_secret_v1" "grafana_admin" {
  count = local.create ? 1 : 0

  metadata {
    name      = local.grafana_admin_secret
    namespace = kubernetes_namespace_v1.this[0].metadata[0].name
    labels    = local.k8s_labels
  }
  data = {
    "admin-user"     = "admin"
    "admin-password" = random_password.grafana_admin[0].result
  }
  type = "Opaque"
}
# ---------------------------------------------------------------------------
# Grafana SSO (#592) — Keycloak OIDC client secret synced from AWS Secrets Manager, plus the gateway-ClusterIP
# lookup backing the split-horizon host-alias. The secret (keycloak-config writes platform/keycloak/grafana-oidc)
# syncs to the `grafana-oidc` K8s secret, injected as GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET. Mirrors ArgoCD/Backstage.
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "grafana_oidc_secret" {
  count = local.grafana_oidc_enabled ? 1 : 0

  manifest = {
    apiVersion = "external-secrets.io/v1beta1"
    kind       = "ExternalSecret"
    metadata = {
      name      = local.grafana_oidc_secret
      namespace = var.namespace
    }
    spec = {
      refreshInterval = "1h"
      secretStoreRef  = { name = var.secret_store_name, kind = "ClusterSecretStore" }
      target          = { name = local.grafana_oidc_secret, creationPolicy = "Owner" }
      data = [{
        secretKey = "client-secret"
        remoteRef = { key = var.grafana_oidc_secret_manager_key, property = "client-secret" }
      }]
    }
  }

  depends_on = [kubernetes_namespace_v1.this]
}

# Current ClusterIP of the shared Cilium gateway Service — backs the OIDC issuer host-alias (never hardcoded;
# self-corrects on apply if the gateway Service is recreated). Mirrors the Backstage module.
data "kubernetes_service_v1" "gateway" {
  count = local.grafana_oidc_alias_on ? 1 : 0

  metadata {
    name      = var.gateway_service_name
    namespace = var.gateway_service_namespace
  }
}
