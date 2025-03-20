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
  path = "${dirname(find_in_parent_folders())}/_envcommon/azure/cilium.hcl"
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