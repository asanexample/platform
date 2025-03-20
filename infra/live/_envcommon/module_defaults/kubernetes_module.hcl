# ---------------------------------------------------------------------------------------------------------------------
# TEMPLATE FOR KUBERNETES MODULE CONFIGURATION
# This is a template for creating new Kubernetes-related modules
# Copy and modify this file when creating new modules that interact with Kubernetes clusters
# ---------------------------------------------------------------------------------------------------------------------

# Include the root `terragrunt.hcl` configuration, which has settings common across all components
include "root" {
  path = find_in_parent_folders()
}

# Include the specialized Kubernetes provider configurations
include "kubernetes_providers" {
  path = "${dirname(find_in_parent_folders())}/_envcommon/kubernetes_providers.hcl"
  expose = true
}

# Default dependencies for Kubernetes modules
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

# Default inputs for Kubernetes modules
inputs = {
  # Kubernetes credentials for provider configuration
  kubernetes_host = dependency.aks_core.outputs.host
  kubernetes_client_certificate = dependency.aks_core.outputs.client_certificate
  kubernetes_client_key = dependency.aks_core.outputs.client_key
  kubernetes_cluster_ca_certificate = dependency.aks_core.outputs.cluster_ca_certificate
} 