/**
 * # ArgoCD Deployment
 *
 * This module deploys ArgoCD on a Kubernetes cluster using Helm.
 */

# Create the namespace if specified
resource "kubernetes_namespace" "argocd" {
  count = var.create_namespace ? 1 : 0

  metadata {
    name = var.namespace

    labels = merge(
      var.namespace_labels,
      {
        "app.kubernetes.io/managed-by" = "terraform"
      }
    )
  }
}

resource "helm_release" "argocd" {
  name             = var.release_name
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = var.chart_version
  namespace        = var.namespace
  create_namespace = var.create_namespace # Allow Helm to create the namespace if needed
  atomic           = true
  cleanup_on_fail  = true
  replace          = true
  timeout          = var.helm_timeout

  values = [
    templatefile("${path.module}/templates/values.yaml", {
      domain                 = var.domain
      high_availability      = var.high_availability
      insecure               = var.insecure
      service_type           = var.service_type
      controller_replicas    = var.high_availability ? 2 : 1
      server_replicas        = var.high_availability ? 2 : 1
      repo_server_replicas   = var.high_availability ? 2 : 1
      app_set_replicas       = var.high_availability ? 2 : 1
      notifications_replicas = var.high_availability ? 2 : 1
      enable_dex             = var.enable_dex
      enable_notifications   = var.enable_notifications
      admin_password         = var.admin_password
    })
  ]

  dynamic "set" {
    for_each = var.additional_set_values
    content {
      name  = set.value.name
      value = set.value.value
      type  = try(set.value.type, null)
    }
  }

  depends_on = [kubernetes_namespace.argocd]
}

# Wait a bit for ArgoCD CRDs to be properly installed before other resources may need them
resource "time_sleep" "wait_for_crds" {
  depends_on = [helm_release.argocd]

  # Give the CRDs time to be properly established in the cluster
  create_duration = "120s"
} 