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

# Include the common configuration for Cilium
include "cilium_common" {
  path = find_in_parent_folders("live/_envcommon/azure/cilium.hcl")
}

# Configure the Kubernetes provider
generate "provider_kubernetes" {
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

# Configure the Helm provider
generate "provider_helm" {
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

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # AKS credentials for provider configuration
  kubernetes_host = dependency.aks_core.outputs.host
  kubernetes_client_certificate = dependency.aks_core.outputs.client_certificate
  kubernetes_client_key = dependency.aks_core.outputs.client_key
  kubernetes_cluster_ca_certificate = dependency.aks_core.outputs.cluster_ca_certificate
  
  # Any environment-specific overrides can be added here
  # set_values = {
  #   # Environment-specific values will be merged with common values
  # }
} 