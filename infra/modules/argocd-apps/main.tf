locals {
  create = var.create

  tenants = local.create ? var.tenants : {}

  tenant_namespaces = { for k, v in local.tenants : k => coalesce(
    v.namespace,
    v.mode == "vcluster" ? "vc-${k}" : "team-${k}",
  ) }
}

resource "kubernetes_manifest" "app_project" {
  for_each = local.tenants

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "AppProject"
    metadata = {
      name      = each.key
      namespace = var.argocd_namespace
    }
    spec = {
      description = "Project for team ${each.key}"
      sourceRepos = [each.value.repo_url]
      destinations = [{
        server    = var.cluster_server
        namespace = local.tenant_namespaces[each.key]
      }]
      namespaceResourceWhitelist = [
        { group = "", kind = "ConfigMap" },
        { group = "", kind = "Secret" },
        { group = "", kind = "Service" },
        { group = "", kind = "ServiceAccount" },
        { group = "apps", kind = "Deployment" },
        { group = "apps", kind = "StatefulSet" },
        { group = "batch", kind = "Job" },
        { group = "batch", kind = "CronJob" },
        { group = "gateway.networking.k8s.io", kind = "HTTPRoute" },
        { group = "external-secrets.io", kind = "ExternalSecret" },
      ]
    }
  }
}

resource "kubernetes_manifest" "application" {
  for_each = local.tenants

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "${each.key}-app"
      namespace = var.argocd_namespace
    }
    spec = {
      project = each.key
      source = {
        repoURL        = each.value.repo_url
        targetRevision = each.value.repo_branch
        path           = each.value.repo_path
      }
      destination = {
        server    = var.cluster_server
        namespace = local.tenant_namespaces[each.key]
      }
      syncPolicy = var.auto_sync ? {
        automated = {
          selfHeal = true
          prune    = true
        }
        syncOptions = ["CreateNamespace=false"]
        } : {
        automated   = null
        syncOptions = null
      }
    }
  }

  depends_on = [kubernetes_manifest.app_project]
}
