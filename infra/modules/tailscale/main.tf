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
      defaultTags = ["tag:k8s-operator"] # Must match oauth_client_tags in tailscale-admin module and ACL policy tag owners
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
            # Kernel-mode subnet routing conflicts with Cilium's eBPF datapath; userspace mode avoids the conflict
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

# Remove ProxyClass finalizers before destroy — operator adds finalizers that block deletion if the operator pod is already gone
resource "null_resource" "proxy_class_finalizer_cleanup" {
  count = local.create && length(var.advertise_routes) > 0 ? 1 : 0

  triggers = {
    proxy_class_name = "${var.cluster_name}-subnet-router"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl patch proxyclass ${self.triggers.proxy_class_name} --type=merge -p '{\"metadata\":{\"finalizers\":null}}' 2>/dev/null || true"
  }

  depends_on = [kubernetes_manifest.proxy_class]
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

# Remove finalizers before destroy so the Connector deletion doesn't block
# waiting for the operator to process the finalizer (which may time out).
resource "null_resource" "connector_finalizer_cleanup" {
  count = local.create && length(var.advertise_routes) > 0 ? 1 : 0

  triggers = {
    connector_name = "${var.cluster_name}-${var.connector_hostname}"
  }

  provisioner "local-exec" {
    when    = destroy
    command = "kubectl patch connector ${self.triggers.connector_name} --type=merge -p '{\"metadata\":{\"finalizers\":null}}' 2>/dev/null || true"
  }

  depends_on = [kubernetes_manifest.connector]
}

# ---------------------------------------------------------------------------
# Split DNS — routes domain queries through VPC DNS via the subnet router.
# Placed here (not in tailscale-admin) so it's created after the subnet
# router is online, avoiding the chicken-and-egg DNS resolution failure.
# ---------------------------------------------------------------------------

resource "tailscale_dns_split_nameservers" "this" {
  for_each = local.create && length(var.advertise_routes) > 0 ? var.split_dns : {}

  domain      = each.key
  nameservers = each.value

  depends_on = [kubernetes_manifest.connector]
}
