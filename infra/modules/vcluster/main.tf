/**
 * ## vCluster Helm Module
 *
 * Deploys vCluster (virtual Kubernetes clusters) on a host cluster using Helm.
 */

locals {
  k8s_labels = {
    for k, v in var.tags :
    replace(lower(k), "/[^a-z0-9_.-]/", "_") => replace(lower(v), "/[^a-z0-9_.-]/", "_")
    if length(replace(lower(k), "/[^a-z0-9_.-]/", "_")) <= 63 && length(replace(lower(v), "/[^a-z0-9_.-]/", "_")) <= 63
  }

  vcluster_values = {
    controlPlane = {
      statefulSet = merge(
        {
          image = { tag = var.vcluster_version }
        },
        var.resource_limits != null ? {
          resources = {
            limits = {
              cpu    = var.resource_limits.cpu
              memory = var.resource_limits.memory
            }
          }
        } : {},
        {
          persistence = {
            volumeClaim = merge(
              { enabled = var.persistence_enabled },
              var.storage_class != null ? { storageClass = var.storage_class } : {},
            )
          }
        },
      )
    }

    sync = {
      toHost = merge(
        var.sync != null ? {
          ingresses      = { enabled = var.sync.ingresses }
          storageClasses = { enabled = var.sync.storage_classes }
        } : {},
        length(var.custom_resource_sync) > 0 ? {
          customResources = {
            for cr in var.custom_resource_sync :
            "${cr.plural}.${cr.group}" => { enabled = true }
          }
        } : {},
      )
      fromHost = var.sync != null ? {
        nodes = { enabled = var.sync.nodes }
      } : {}
    }

    policies = {
      resourceQuota = { enabled = var.policies.resource_quota }
      limitRange    = { enabled = var.policies.limit_range }
      networkPolicy = { enabled = var.policies.network_policy }
    }
  }
}

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

  values = [
    yamlencode(local.vcluster_values),
    var.values != "" ? var.values : "{}",
  ]

  depends_on = [kubernetes_namespace.vcluster]
}
