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

# Strip the operator-managed finalizers off the Connector + ProxyClass before destroy, so their deletion
# doesn't hang waiting for the (concurrently-removed) operator to process them. Runs FIRST on teardown
# (depends_on => reverse-order destroy). Uses scripts/k8s-finalizer-clear.sh, which sets up its own cluster
# auth (aws eks update-kubeconfig + the deployer role) — the previous bare `kubectl patch` had no guaranteed
# context during teardown and silently no-op'd, which is what hung the subnet-router delete. Best-effort.
#
# The script path is resolved at RUN TIME via `git rev-parse --show-toplevel`, not baked into `triggers` as
# an absolute path — a worktree's checkout lives at a different absolute path than the main checkout, which
# would otherwise make a worktree apply look like a changed trigger and force a replace (firing this
# `when = destroy` provisioner outside of an actual teardown).
resource "null_resource" "crd_finalizer_cleanup" {
  count = local.create && length(var.advertise_routes) > 0 && var.finalizer_clear_script != "" ? 1 : 0

  triggers = {
    cluster  = var.cluster_name
    region   = var.region
    role_arn = var.deployer_role_arn
    # Fully-qualified resource names (group-suffixed) are REQUIRED: Dex also registers a `connectors` kind
    # (connectors.dex.coreos.com), so the bare `connector/...` is ambiguous and `kubectl` resolves it to the
    # wrong group — the patch silently no-ops ("nothing to clear") and the Connector's finalizer is never
    # removed, hanging its deletion until the wait times out (~10m). Qualify to tailscale.com to disambiguate.
    refs = "connectors.tailscale.com/${var.cluster_name}-${var.connector_hostname} proxyclasses.tailscale.com/${var.cluster_name}-subnet-router"
  }

  provisioner "local-exec" {
    when = destroy
    # cluster-scoped CRs (Connector/ProxyClass) -> namespace arg is "-". --delete so the provisioner issues the
    # deletion itself (operator, still up, deprovisions the tailnet device) and force-clears the finalizer in one
    # shot — terraform's later manifest delete is then a clean no-op, with no window for the operator to re-add.
    command = "bash \"$(git rev-parse --show-toplevel)/scripts/k8s-finalizer-clear.sh\" --delete ${self.triggers.cluster} ${self.triggers.region} ${self.triggers.role_arn} - ${self.triggers.refs}"
  }

  depends_on = [kubernetes_manifest.connector, kubernetes_manifest.proxy_class]
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
