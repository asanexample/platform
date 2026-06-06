locals {
  create = var.create
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
# Gateway — Cilium Gateway API with TLS termination (the shared, foundational
# ingress for *.<domain>). HTTPRoutes are owned by each app / the gateway-config
# routes unit and attach here via parentRef. GatewayClass "cilium" is created by
# the Cilium Helm chart, not managed here.
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
        # Both scheme and internal annotations set for compat with LB Controller v1 and v2
        annotations = merge(
          {
            "service.beta.kubernetes.io/aws-load-balancer-type" = "nlb"
          },
          var.internal ? {
            "service.beta.kubernetes.io/aws-load-balancer-scheme"   = "internal"
            "service.beta.kubernetes.io/aws-load-balancer-internal" = "true"
          } : {}
        )
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
        # HTTP listener exists only to support HTTP->HTTPS 301 redirects (the redirect routes live with the apps)
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

  depends_on = [kubernetes_manifest.cluster_issuer]
}
