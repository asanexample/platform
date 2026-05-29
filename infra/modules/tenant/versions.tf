terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
    # Required by the vcluster sub-module
    helm = {
      source  = "hashicorp/helm"
      version = ">= 3.0"
    }
  }
}
