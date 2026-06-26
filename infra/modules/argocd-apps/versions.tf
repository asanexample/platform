terraform {
  required_version = ">= 1.5"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.0"
    }
    # ADR-071: the per-Product ApplicationSet (recursive merge generator) is delivered via a passthrough Helm
    # chart — kubernetes_manifest cannot represent ArgoCD's self-referential generators schema.
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.0"
    }
  }
}
