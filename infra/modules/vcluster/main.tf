/**
 * # vCluster Helm Module
 *
 * This module deploys vCluster (virtual Kubernetes clusters) on a host cluster using Helm.
 */

locals {
  # Prepare Kubernetes labels from tags, replacing any characters not allowed in labels
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }
}

# Create the namespace for the vCluster
resource "kubernetes_namespace" "vcluster" {
  count = var.create ? 1 : 0

  metadata {
    name = var.namespace

    labels = merge(
      local.k8s_labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
        "app.kubernetes.io/part-of"    = "vcluster"
        "vcluster.loft.sh/cluster"     = var.cluster_name
      }
    )
  }
}

# Deploy vCluster using Helm
resource "helm_release" "vcluster" {
  count            = var.create ? 1 : 0
  name             = var.cluster_name
  repository       = "https://charts.loft.sh"
  chart            = "vcluster"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = false
  timeout          = 600
  wait             = true
  atomic           = true
  cleanup_on_fail  = true
  replace          = true

  values = [yamlencode(merge(
    {
      vcluster = {
        image = {
          tag = var.vcluster_version
        }
      }
    },
    var.resource_limits != null ? {
      syncer = {
        resources = {
          limits = {
            cpu    = var.resource_limits.cpu
            memory = var.resource_limits.memory
          }
        }
      }
    } : {},
    var.sync != null ? {
      sync = {
        nodes          = { enabled = var.sync.nodes }
        ingresses      = { enabled = var.sync.ingresses }
        storageClasses = { enabled = var.sync.storage_classes }
      }
    } : {},
    var.isolation != null ? {
      isolation = merge(
        { enabled = true, networkPolicy = { enabled = var.isolation.network_policy } },
        var.isolation.limit_range != null ? { limitRange = { enabled = var.isolation.limit_range.enabled } } : {},
        var.isolation.resource_quota != null ? { resourceQuota = { enabled = var.isolation.resource_quota.enabled } } : {},
      )
    } : {},
    var.ingress != null && var.ingress.enabled ? merge(
      { ingress = merge(
        { enabled = true },
        var.ingress.host != "" ? { host = var.ingress.host } : {},
        var.ingress.ingress_class != "" ? { ingressClassName = var.ingress.ingress_class } : {},
        var.ingress.tls_secret != "" ? { tls = [{ secretName = var.ingress.tls_secret }] } : {},
      ) },
    ) : {},
    var.storage_class != null ? {
      storage = { className = var.storage_class }
    } : {},
    length(var.custom_resource_sync) > 0 ? {
      experimental = {
        syncSettings = {
          syncToHost = {
            customResources = { for cr in var.custom_resource_sync : cr.kind => { enabled = true } }
          }
        }
      }
    } : {},
  )), var.values != "" ? var.values : "{}"]

  depends_on = [kubernetes_namespace.vcluster]
}
