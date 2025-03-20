# ---------------------------------------------------------------------------------------------------------------------
# COMMON KUBERNETES PROVIDER CONFIGURATIONS
# This file defines Kubernetes-specific provider configurations that can be reused across multiple Terraform modules
# ---------------------------------------------------------------------------------------------------------------------

# ---------------------------------------------------------------------------------------------------------------------
# SPECIALIZED PROVIDER CONFIGURATIONS FOR KUBERNETES/HELM
# These provider configurations are specifically designed for modules that interact with Kubernetes clusters
# ---------------------------------------------------------------------------------------------------------------------

# Generator for standard Kubernetes provider configuration
generate "kubernetes_provider" {
  path      = "kubernetes_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "kubernetes" {
  host                   = var.kubernetes_host
  client_certificate     = base64decode(var.kubernetes_client_certificate)
  client_key             = base64decode(var.kubernetes_client_key)
  cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
}
EOF
}

# Generator for standard Helm provider configuration
generate "helm_provider" {
  path      = "helm_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "helm" {
  kubernetes {
    host                   = var.kubernetes_host
    client_certificate     = base64decode(var.kubernetes_client_certificate)
    client_key             = base64decode(var.kubernetes_client_key)
    cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
  }
}
EOF
}

# Common inputs needed for Kubernetes providers that should be provided by including modules
inputs = {
  kubernetes_host = null  # Must be provided by the module using this configuration
  kubernetes_client_certificate = null  # Must be provided by the module using this configuration
  kubernetes_client_key = null  # Must be provided by the module using this configuration
  kubernetes_cluster_ca_certificate = null  # Must be provided by the module using this configuration
} 