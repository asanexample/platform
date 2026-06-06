locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# App HTTPRoutes — one per hostname, attached to the shared Gateway (created by the `gateway` module/unit via
# parentRef). The foundational Gateway + ClusterIssuer live in the `gateway` module (ADR-053/059); this unit owns
# only the per-app routes. (Keycloak self-owns its route in the keycloak module so its endpoint is up early.)
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "http_routes" {
  for_each = local.create ? var.routes : {}

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = each.key
      namespace = each.value.namespace
    }
    spec = {
      parentRefs = [{
        name        = var.gateway_name
        namespace   = var.gateway_namespace
        sectionName = "https"
      }]
      hostnames = ["${each.key}.${var.domain}"] # Map key is the hostname prefix (e.g., "argocd" -> "argocd.aws.refplat.org")
      rules = [{
        backendRefs = [{
          name = each.value.service
          port = each.value.port
        }]
      }]
    }
  }
}

# ---------------------------------------------------------------------------
# HTTP→HTTPS redirect routes
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "http_redirect_routes" {
  for_each = local.create ? var.routes : {}

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "HTTPRoute"
    metadata = {
      name      = "${each.key}-redirect"
      namespace = each.value.namespace
    }
    spec = {
      parentRefs = [{
        name        = var.gateway_name
        namespace   = var.gateway_namespace
        sectionName = "http"
      }]
      hostnames = ["${each.key}.${var.domain}"]
      rules = [{
        filters = [{
          type = "RequestRedirect"
          requestRedirect = {
            scheme     = "https"
            statusCode = 301
          }
        }]
      }]
    }
  }
}
