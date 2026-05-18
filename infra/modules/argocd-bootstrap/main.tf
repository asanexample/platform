/**
 * # ArgoCD Bootstrap Module
 *
 * This module handles the bootstrap applications configuration for ArgoCD.
 */

# Create cert-manager application
resource "kubernetes_manifest" "cert_manager" {
  count = length(var.bootstrap_applications) > 0 ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "cert-manager-ops-wus"
      namespace = var.argocd_namespace
      annotations = {
        "argocd.argoproj.io/sync-wave" = "0"
      }
    }
    spec = {
      project = var.project
      source = {
        repoURL        = "https://charts.jetstack.io"
        chart          = "cert-manager"
        targetRevision = "v1.12.0"
        helm = {
          values = "installCRDs: true"
        }
      }
      destination = {
        server    = var.server
        namespace = "cert-manager"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}

# Create external-dns application
resource "kubernetes_manifest" "external_dns" {
  count = length(var.bootstrap_applications) > 0 ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "external-dns-ops-wus"
      namespace = var.argocd_namespace
      annotations = {
        "argocd.argoproj.io/sync-wave" = "1"
      }
    }
    spec = {
      project = var.project
      source = {
        repoURL        = "https://kubernetes-sigs.github.io/external-dns"
        chart          = "external-dns"
        targetRevision = "1.13.1"
      }
      destination = {
        server    = var.server
        namespace = "external-dns"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
}

# Create external-secrets application
resource "kubernetes_manifest" "external_secrets" {
  count = length(var.bootstrap_applications) > 0 ? 1 : 0

  manifest = {
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "external-secrets-ops-wus"
      namespace = var.argocd_namespace
      annotations = {
        "argocd.argoproj.io/sync-wave" = "1"
      }
    }
    spec = {
      project = var.project
      source = {
        repoURL        = "https://charts.external-secrets.io"
        chart          = "external-secrets"
        targetRevision = "0.9.5"
      }
      destination = {
        server    = var.server
        namespace = "external-secrets"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = ["CreateNamespace=true"]
      }
    }
  }
} 