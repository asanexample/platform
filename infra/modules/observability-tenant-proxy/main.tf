locals {
  create = var.create
  # k8s LABEL values only — NOT var.tags (AWS tag values like "Multi-Cloud Platform" contain spaces, which
  # k8s label values reject). var.tags is not applied to k8s objects.
  labels   = { "app.kubernetes.io/name" = "tenant-proxy", "app.kubernetes.io/part-of" = "observability", "app.kubernetes.io/managed-by" = "terraform" }
  selector = { app = "tenant-proxy" }
}

# ---------------------------------------------------------------------------
# The proxy Deployment — the fail-closed read front door (P13, #590). Verifies the Grafana-forwarded
# X-Id-Token, resolves the caller's groups → tenant scope, stamps X-Scope-OrgID, proxies to Mimir.
# ---------------------------------------------------------------------------
resource "kubernetes_deployment_v1" "tenant_proxy" {
  count = local.create ? 1 : 0

  metadata {
    name      = "tenant-proxy"
    namespace = var.namespace
    labels    = local.labels
  }

  spec {
    replicas = var.replicas
    selector {
      match_labels = local.selector
    }
    template {
      metadata {
        labels = merge(local.labels, local.selector)
      }
      spec {
        security_context {
          run_as_non_root = true
          run_as_user     = 65532
          seccomp_profile { type = "RuntimeDefault" }
        }
        container {
          name  = "tenant-proxy"
          image = var.image

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            capabilities { drop = ["ALL"] }
          }
          resources {
            requests = { cpu = "20m", memory = "48Mi" }
            limits   = { memory = "128Mi" }
          }

          port {
            name           = "proxy"
            container_port = 8080
          }
          port {
            name           = "metrics"
            container_port = 9090
          }

          env {
            name  = "UPSTREAM_URL"
            value = var.upstream_url
          }
          env {
            name  = "JWKS_URL"
            value = var.jwks_url
          }
          env {
            name  = "OIDC_ISSUER"
            value = var.oidc_issuer
          }
          env {
            name  = "OIDC_AUDIENCE"
            value = var.oidc_audience
          }
          env {
            name  = "TENANTS"
            value = join(",", var.tenants)
          }
          env {
            name  = "ADMIN_GROUP"
            value = var.admin_group
          }
          # Cross-team read grants → GRANTS = "grantee:owner1,owner2;grantee2:owner3" (empty when none).
          env {
            name  = "GRANTS"
            value = join(";", [for grantee, owners in var.grants : "${grantee}:${join(",", owners)}"])
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 9090
            }
            initial_delay_seconds = 5
            period_seconds        = 20
          }
          readiness_probe {
            http_get {
              path = "/healthz"
              port = 9090
            }
            initial_delay_seconds = 3
            period_seconds        = 10
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "tenant_proxy" {
  count = local.create ? 1 : 0

  metadata {
    name      = "tenant-proxy"
    namespace = var.namespace
    labels    = local.labels
  }
  spec {
    selector = local.selector
    port {
      name        = "proxy"
      port        = 8080
      target_port = 8080
    }
    port {
      name        = "metrics"
      port        = 9090
      target_port = 9090
    }
  }
}

# ServiceMonitor — the ServiceMonitor CRD ships with kube-prometheus-stack, so kubernetes_manifest is fine.
resource "kubernetes_manifest" "tenant_proxy_service_monitor" {
  count = local.create && var.create_service_monitor ? 1 : 0

  manifest = {
    apiVersion = "monitoring.coreos.com/v1"
    kind       = "ServiceMonitor"
    metadata = {
      name      = "tenant-proxy"
      namespace = var.namespace
    }
    spec = {
      selector  = { matchLabels = local.selector }
      endpoints = [{ port = "metrics", path = "/metrics", interval = "30s" }]
    }
  }

  depends_on = [kubernetes_service_v1.tenant_proxy]
}

# ---------------------------------------------------------------------------
# The per-team Grafana datasource (the enforcement point). oauthPassThru forwards the user's OIDC token
# to the proxy as X-Id-Token; the proxy scopes the query to the caller's team tenant. Provisioned via the
# Grafana sidecar (label grafana_datasource=1), same mechanism as the Mimir datasources.
# ---------------------------------------------------------------------------
resource "kubernetes_config_map_v1" "datasource" {
  count = local.create && var.create_datasource ? 1 : 0

  metadata {
    name      = "tenant-proxy-datasource"
    namespace = var.namespace
    labels    = merge(local.labels, { grafana_datasource = "1" })
  }
  data = {
    "tenant-proxy-datasource.yaml" = yamlencode({
      apiVersion = 1
      datasources = [{
        name      = var.datasource_name
        type      = "prometheus"
        access    = "proxy"
        uid       = "mimir-team"
        url       = "http://tenant-proxy.${var.namespace}.svc:8080"
        isDefault = false
        jsonData = {
          # Forward the logged-in user's OIDC token to the proxy (confirmed as X-Id-Token, #590 spike);
          # the proxy verifies it and scopes the query to the caller's team tenant.
          oauthPassThru = true
          httpMethod    = "POST"
        }
      }]
    })
  }
}
