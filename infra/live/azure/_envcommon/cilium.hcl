# ---------------------------------------------------------------------------------------------------------------------
# COMMON TERRAGRUNT CONFIGURATION FOR CILIUM CNI
# This is the common component configuration for Cilium CNI. The common parameters defined in this file will be
# used as defaults for all environments, which minimizes duplication across environments.
# ---------------------------------------------------------------------------------------------------------------------

# Terraform module source for Cilium
terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//kubernetes/cilium"
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