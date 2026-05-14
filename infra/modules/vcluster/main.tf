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

  values = var.values != "" ? [var.values] : []

  # vCluster app version
  set {
    name  = "vcluster.image.tag"
    value = var.vcluster_version
  }

  # Resource limits for the syncer
  dynamic "set" {
    for_each = var.resource_limits != null ? [var.resource_limits] : []
    content {
      name  = "syncer.resources.limits.cpu"
      value = set.value.cpu
    }
  }

  dynamic "set" {
    for_each = var.resource_limits != null ? [var.resource_limits] : []
    content {
      name  = "syncer.resources.limits.memory"
      value = set.value.memory
    }
  }

  # Sync configuration
  dynamic "set" {
    for_each = var.sync != null ? [var.sync] : []
    content {
      name  = "sync.nodes.enabled"
      value = tostring(set.value.nodes)
    }
  }

  dynamic "set" {
    for_each = var.sync != null ? [var.sync] : []
    content {
      name  = "sync.ingresses.enabled"
      value = tostring(set.value.ingresses)
    }
  }

  dynamic "set" {
    for_each = var.sync != null ? [var.sync] : []
    content {
      name  = "sync.storageClasses.enabled"
      value = tostring(set.value.storage_classes)
    }
  }

  # Isolation settings
  dynamic "set" {
    for_each = var.isolation != null ? [var.isolation] : []
    content {
      name  = "isolation.enabled"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = var.isolation != null ? [var.isolation] : []
    content {
      name  = "isolation.networkPolicy.enabled"
      value = tostring(set.value.network_policy)
    }
  }

  dynamic "set" {
    for_each = var.isolation != null && var.isolation.limit_range != null ? [var.isolation.limit_range] : []
    content {
      name  = "isolation.limitRange.enabled"
      value = tostring(set.value.enabled)
    }
  }

  dynamic "set" {
    for_each = var.isolation != null && var.isolation.resource_quota != null ? [var.isolation.resource_quota] : []
    content {
      name  = "isolation.resourceQuota.enabled"
      value = tostring(set.value.enabled)
    }
  }

  # Ingress configuration
  dynamic "set" {
    for_each = var.ingress != null && var.ingress.enabled ? [var.ingress] : []
    content {
      name  = "ingress.enabled"
      value = "true"
    }
  }

  dynamic "set" {
    for_each = var.ingress != null && var.ingress.enabled && var.ingress.host != "" ? [var.ingress] : []
    content {
      name  = "ingress.host"
      value = set.value.host
    }
  }

  dynamic "set" {
    for_each = var.ingress != null && var.ingress.enabled && var.ingress.ingress_class != "" ? [var.ingress] : []
    content {
      name  = "ingress.ingressClassName"
      value = set.value.ingress_class
    }
  }

  dynamic "set" {
    for_each = var.ingress != null && var.ingress.enabled && var.ingress.tls_secret != "" ? [var.ingress] : []
    content {
      name  = "ingress.tls[0].secretName"
      value = set.value.tls_secret
    }
  }

  # Storage class
  dynamic "set" {
    for_each = var.storage_class != null ? [var.storage_class] : []
    content {
      name  = "storage.className"
      value = set.value
    }
  }

  depends_on = [kubernetes_namespace.vcluster]
}
