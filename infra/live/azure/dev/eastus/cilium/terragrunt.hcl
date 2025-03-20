# Terragrunt configuration for Cilium CNI in eastus region

# Local variables for this configuration
locals {
  # Load hierarchical variables
  env_vars     = read_terragrunt_config(find_in_parent_folders("env.hcl"))
  region_vars  = read_terragrunt_config(find_in_parent_folders("region.hcl"))
  network_vars = read_terragrunt_config(find_in_parent_folders("network.hcl"))
  common_vars  = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  
  # Merge all variables for convenience
  all_vars = merge(
    local.env_vars.locals,
    local.region_vars.locals,
    local.network_vars.locals,
    local.common_vars.locals
  )
  
  # Extract commonly used variables
  env         = local.env_vars.locals.environment
  prefix      = local.common_vars.locals.prefix
  customer    = local.common_vars.locals.customer
  region      = local.region_vars.locals.region
  region_abbv = local.region_vars.locals.region_abbv
  tags        = merge(
    local.common_vars.locals.tags, 
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Include the common configuration for Cilium
include "cilium_common" {
  path = find_in_parent_folders("azure/_envcommon/cilium.hcl")
}

# Configure the Kubernetes provider
generate "provider_kubernetes" {
  path      = "kubernetes_provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "kubernetes" {
  host = var.kubernetes_host
  
  # Only attempt to decode if not "REDACTED" (used in mock outputs)
  client_certificate     = var.kubernetes_client_certificate != "REDACTED" ? base64decode(var.kubernetes_client_certificate) : null
  client_key             = var.kubernetes_client_key != "REDACTED" ? base64decode(var.kubernetes_client_key) : null
  cluster_ca_certificate = var.kubernetes_cluster_ca_certificate != "REDACTED" ? base64decode(var.kubernetes_cluster_ca_certificate) : null
  
  # Skip TLS verification in case of mock/test runs
  insecure = var.kubernetes_client_certificate == "REDACTED" ? true : false
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
    host = var.kubernetes_host
    
    # Only attempt to decode if not "REDACTED" (used in mock outputs)
    client_certificate     = var.kubernetes_client_certificate != "REDACTED" ? base64decode(var.kubernetes_client_certificate) : null
    client_key             = var.kubernetes_client_key != "REDACTED" ? base64decode(var.kubernetes_client_key) : null
    cluster_ca_certificate = var.kubernetes_cluster_ca_certificate != "REDACTED" ? base64decode(var.kubernetes_cluster_ca_certificate) : null
    
    # Skip TLS verification in case of mock/test runs
    insecure = var.kubernetes_client_certificate == "REDACTED" ? true : false
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
    location = local.region
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

dependency "aks_node_pools" {
  config_path = "../aks_node_pools"
  
  # Mock outputs for plan and validation
  mock_outputs = {
    app_node_pool_id = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks/agentPools/apps"
  }
}

# Specify inputs specific to this module (these will merge with the common inputs)
inputs = {
  # Environment variables
  environment = local.env
  customer = local.customer
  prefix = local.prefix
  region_abbv = local.region_abbv

  # AKS credentials for provider configuration
  kubernetes_host = dependency.aks_core.outputs.host
  kubernetes_client_certificate = dependency.aks_core.outputs.client_certificate
  kubernetes_client_key = dependency.aks_core.outputs.client_key
  kubernetes_cluster_ca_certificate = dependency.aks_core.outputs.cluster_ca_certificate
  
  # Add custom module dependency
  module_depends_on = [dependency.aks_node_pools.outputs.app_node_pool_id]
  
  # Set longer timeout for Helm
  helm_timeout = 1200  # 20 minutes
  
  # Any environment-specific overrides can be added here
  # set_values = {
  #   # Environment-specific values will be merged with common values
  # }
} 
