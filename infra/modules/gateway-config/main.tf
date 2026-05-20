locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# GatewayClass — Cilium
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "gateway_class" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "GatewayClass"
    metadata = {
      name = "cilium"
    }
    spec = {
      controllerName = "io.cilium/gateway-controller"
    }
  }
}

# ---------------------------------------------------------------------------
# ClusterIssuer — Let's Encrypt production via Route53 DNS01
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "cluster_issuer" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "cert-manager.io/v1"
    kind       = "ClusterIssuer"
    metadata = {
      name = var.cluster_issuer_name
    }
    spec = {
      acme = {
        server = "https://acme-v02.api.letsencrypt.org/directory"
        email  = var.letsencrypt_email
        privateKeySecretRef = {
          name = "${var.cluster_issuer_name}-account-key"
        }
        solvers = [{
          dns01 = {
            route53 = {
              region       = var.route53_region
              hostedZoneID = var.route53_hosted_zone_id
            }
          }
        }]
      }
    }
  }
}

# ---------------------------------------------------------------------------
# Gateway — Cilium Gateway API with TLS termination
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "gateway" {
  count = local.create ? 1 : 0

  manifest = {
    apiVersion = "gateway.networking.k8s.io/v1"
    kind       = "Gateway"
    metadata = {
      name      = var.gateway_name
      namespace = var.gateway_namespace
      annotations = {
        "cert-manager.io/cluster-issuer" = var.cluster_issuer_name
      }
    }
    spec = {
      gatewayClassName = "cilium"
      infrastructure = {
        annotations = {
          "service.beta.kubernetes.io/aws-load-balancer-type"   = "nlb"
          "service.beta.kubernetes.io/aws-load-balancer-scheme" = "internet-facing"
        }
      }
      listeners = [
        {
          name     = "https"
          protocol = "HTTPS"
          port     = 443
          hostname = "*.${var.domain}"
          tls = {
            mode = "Terminate"
            certificateRefs = [{
              name = "${var.gateway_name}-tls"
            }]
          }
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
        {
          name     = "http"
          protocol = "HTTP"
          port     = 80
          hostname = "*.${var.domain}"
          allowedRoutes = {
            namespaces = {
              from = "All"
            }
          }
        },
      ]
    }
  }

  depends_on = [kubernetes_manifest.gateway_class, kubernetes_manifest.cluster_issuer]
}

# ---------------------------------------------------------------------------
# HTTPRoutes — one per hostname
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
      hostnames = ["${each.key}.${var.domain}"]
      rules = [{
        backendRefs = [{
          name = each.value.service
          port = each.value.port
        }]
      }]
    }
  }

  depends_on = [kubernetes_manifest.gateway]
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

  depends_on = [kubernetes_manifest.gateway]
}
