locals {
  create = var.create

  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  tailscale_values = {
    oauth = {
      clientId     = local.oauth_client_id
      clientSecret = local.oauth_client_secret
    }
    operatorConfig = {
      defaultTags = ["tag:k8s-operator"]
    }
    podLabels = local.k8s_labels
  }
}

# ---------------------------------------------------------------------------
# Helm Release — Tailscale Kubernetes Operator
# ---------------------------------------------------------------------------

resource "helm_release" "tailscale_operator" {
  count            = local.create ? 1 : 0
  name             = var.helm_release_name
  repository       = var.helm_repository
  chart            = var.helm_chart
  version          = var.helm_chart_version
  namespace        = var.namespace
  create_namespace = true
  timeout          = var.helm_timeout
  wait             = var.helm_wait
  atomic           = var.helm_wait
  cleanup_on_fail  = true
  replace          = true

  values = [yamlencode(local.tailscale_values)]
}

# ---------------------------------------------------------------------------
# Connector — Subnet router advertising VPC CIDR to the tailnet
# ---------------------------------------------------------------------------

resource "kubernetes_manifest" "proxy_class" {
  count = local.create && length(var.advertise_routes) > 0 ? 1 : 0

  manifest = {
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "ProxyClass"
    metadata = {
      name = "${var.cluster_name}-subnet-router"
    }
    spec = {
      statefulSet = {
        pod = {
          tailscaleContainer = {
            env = [
              {
                name  = "TS_USERSPACE"
                value = "true"
              }
            ]
          }
        }
      }
    }
  }

  depends_on = [helm_release.tailscale_operator]
}

resource "kubernetes_manifest" "connector" {
  count = local.create && length(var.advertise_routes) > 0 ? 1 : 0

  manifest = {
    apiVersion = "tailscale.com/v1alpha1"
    kind       = "Connector"
    metadata = {
      name = "${var.cluster_name}-${var.connector_hostname}"
    }
    spec = {
      hostname   = "${var.cluster_name}-${var.connector_hostname}"
      proxyClass = "${var.cluster_name}-subnet-router"
      subnetRouter = {
        advertiseRoutes = var.advertise_routes
      }
    }
  }

  depends_on = [kubernetes_manifest.proxy_class]
}
