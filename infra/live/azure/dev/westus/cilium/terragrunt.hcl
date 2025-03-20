# Terragrunt configuration for Cilium CNI in westus region

# Local variables for this configuration
locals {
  # Load common variables
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Extract commonly used variables
  env         = local.common_vars.locals.env
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = "westus"
  region_abbv = "wus"
  tags        = local.common_vars.locals.tags
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Use the Cilium module
terraform {
  source = "${get_repo_root()}/infra/modules/azure/kubernetes/cilium"
}

# Set dependencies for this module
dependency "naming" {
  config_path = "../naming"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    aks_cluster = "mock-aks"
  }
}

dependency "resource_group" {
  config_path = "../resource_group"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    name = "mock-rg"
    location = "westus"
  }
}

dependency "aks_core" {
  config_path = "../aks_core"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
    name = "mock-aks"
    host = "https://mock-aks-api-server.azure.com"
    client_certificate = "REDACTED"
    client_key = "REDACTED"
    cluster_ca_certificate = "REDACTED"
    kube_config_raw = "REDACTED"
  }
}

# Configure the Kubernetes provider
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

# Configure the Helm provider
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

# Specify inputs specific to this module
inputs = {
  # Cilium configuration
  namespace     = "kube-system"
  chart_version = "1.17.2"
  
  # AKS credentials for provider configuration
  kubernetes_host = dependency.aks_core.outputs.host
  kubernetes_client_certificate = dependency.aks_core.outputs.client_certificate
  kubernetes_client_key = dependency.aks_core.outputs.client_key
  kubernetes_cluster_ca_certificate = dependency.aks_core.outputs.cluster_ca_certificate
  
  # Default Cilium settings
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
  
  # Other module parameters
  helm_timeout = 1200
  wait         = true
} 