# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR CILIUM CNI INSTALLATION
# This is the common component configuration for Cilium CNI. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration, which has settings common across all components
include "root" {
  path = find_in_parent_folders()
}

# Terraform module source for Cilium
terraform {
  source = "${dirname(find_in_parent_folders())}/modules/azure/kubernetes/cilium"
}

# ---------------------------------------------------------------------------------------------------------------------
# DEPENDENCIES AND PROVIDERS
# These configurations manage the dependencies needed for Cilium and configure necessary providers
# ---------------------------------------------------------------------------------------------------------------------

# Configure the Kubernetes provider for Cilium to communicate with the AKS cluster
generate "provider_k8s" {
  path      = "kubernetes_provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
provider "kubernetes" {
  host                   = var.kubernetes_host
  client_certificate     = base64decode(var.kubernetes_client_certificate)
  client_key             = base64decode(var.kubernetes_client_key)
  cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
}
EOF
}

# Configure the Helm provider for installing Cilium charts
generate "provider_helm" {
  path      = "helm_provider_override.tf"
  if_exists = "overwrite_terragrunt"
  contents = <<EOF
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

# ---------------------------------------------------------------------------------------------------------------------
# MODULE PARAMETERS
# These are the variables we have to pass in to use the module. This defines the parameters that are common across all
# environments.
# ---------------------------------------------------------------------------------------------------------------------
inputs = {
  # Cilium configuration
  namespace     = "kube-system"
  chart_version = "1.17.2"
  
  # Default Cilium settings applied to all environments
  # These can be overridden in environment-specific configurations
  set_values = {
    "aks.enabled"                 = "true"
    "tunnel"                      = "vxlan"
    "ipam.mode"                   = "kubernetes"
    "kubeProxyReplacement"        = "strict"
    "hubble.enabled"              = "true"
    "hubble.relay.enabled"        = "true"
    "hubble.ui.enabled"           = "true"
    "operator.replicas"           = "2"
    "nodeinit.enabled"            = "true"
    "prometheus.enabled"          = "true"
    "prometheus.serviceMonitor.enabled" = "false"
  }
  
  # Other standard configuration parameters
  helm_timeout = 1200
  wait         = true
} 