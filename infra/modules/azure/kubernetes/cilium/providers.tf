/**
 * Provider configuration for the Cilium CNI Installation Module
 */

# The Kubernetes provider is configured by the kubeconfig or exec arguments
provider "kubernetes" {
  # Configuration will come from the caller module
}

# The Helm provider is configured by the kubeconfig or exec arguments
provider "helm" {
  kubernetes {
    # Configuration will come from the caller module
  }
} 