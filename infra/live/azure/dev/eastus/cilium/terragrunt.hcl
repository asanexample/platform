/**
 * # Cilium CNI Deployment
 *
 * This Terragrunt configuration deploys Cilium CNI on an existing AKS cluster.
 */

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
  tags = merge(
    local.common_vars.locals.tags,
    local.env_vars.locals.env_tags,
    local.region_vars.locals.region_tags
  )
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Terraform source - use relative path from this directory to the module
terraform {
  source = "../../../../../modules/cilium"
}

# Define dependencies - this Cilium module depends on the AKS cluster
dependency "aks" {
  config_path = "../aks_core"

  # Wait for the AKS cluster to be fully deployed
  skip_outputs = false

  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group_name    = "mock-rg"
    name                   = "mock-aks"
    host                   = "https://mock-aks-api-server.hcp.eastus.azmk8s.io:443"
    cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUVMVENDQXBXZ0F3SUJBZ0lSQU1lTmFXNzVKUCttREcvWXJVaXZKR2t3RFFZSktvWklodmNOQVFFTEJRQXcKRFRFTE1Ba0dBMVVFQXhNQ1kyRXdJQmNOTWpRd016STJNREV3TVRJNVdoZ1BNakExTkRBek1qWXdNVEV4TWpsYQpNQTB4Q3pBSkJnTlZCQU1UQW1OaE1JSUNJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBZzhBTUlJQ0NnS0NBZ0VBCnE2WTJ5SUI2NHpkdXpFdk1PSjM2dURPM3ExRGFrTmdyaFRFNHpLaFc2QjJZeUVpSW4rcWVFVVVxUll0RkNka3oKTzJYeUlKVGg1RVVSc0NCdTlrWm82QW9CczgrYmFLN0xnSXFnZ2RjQU56Zmp0MXVIRkZ4TnJ2Y1pDNElhdm13UwpRem9HdlkwZFgwQnZTcFprbUx0TVhxZDdTekVIOUpPVEpQRlJBQ0d6WVVES3VxVXptZ0czaDlUY2s3cHBTNm0vCmttSlNTWldHYnd5OVJxRXQzZk1BZlJINGtnVDRxZFZZMjR0NjdCRkxlNDduTWJQTStEbGttUWJWVUFhNE85UU0KZnE2RVJpZUlUdk0xVzhLZWhQblNHUUFKbWRQM1lheVZtL3djbS9lbTBVRmYzWStzWUNQcmYveGRJNHdyQXdzbwpzSE1Pcm9kS29EUmJjNFU2TFNZTVZKRVlTTHQvUS9PazAyMkVlNlkwVUJEOUc5NXgraE9oRERPZUZjWi9LYlJJCjZxSGxGU0ZSa3o1Qy9HeVJvbUhFbk5iQnhOb3A4ZVZsVXB0ZGdBYnNBRmZNMExCTFlzZ2NtRndORERud2NkdTEKZFF1V294SVV0S2dUL2lkbzY2NEpqYXhuMWs5Z3kvMlRVY3BQZ0k0bGFnMCtYRFJROW5YbURIV3BKUmZXeERVagpCcE9ZczRQRGpBd3hpeFJHWnVtbXA0MlNtRS9VRUhIQnRua3Bid2NiWExzMzkwVFRLdmtHL2tKSWsvL2pWYW1OCmI3L0RvZW5GY1ArdzRjL21MZ1M5aTFpYnRQMkZoNWNLcmRXWGdKWmVnVE1GOXZNZXRCKzJnTUhaUU9QbVdQaCsKS2NMcnlvMVNqNnVqdVE1UkM0OXY2UkExRFZFM3BsR0x2cDlvd2ZzQ0F3RUFBYU5DTUVBd0RnWURWUjBQQVFILwpCQVFEQWdJRU1BOEdBMVVkRXdFQi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZJaXpZZ1NRbnRHNXEzb0JVK2taCnozWURYT0NRTUEwR0NTcUdTSWIzRFFFQkN3VUFBNElCQVFDSTFJaGdWU3I3VWs2a0FwMWpKRmE0LzFENkswaisKOGE1TG5pUHVNS1lOeWFibU9GNDVueUoyWXZZYmRMd1VYKy8wVVVyRVVnOHQvL3ZyYnFNMjgxbHlob0lZdEpLWApYM0dpWEFzQ2xBZWdQNTdtNEQ1TWJtZFgxL0FLbjVxcmJtbjZmRWRaZzJNdDdmTWRBeTRzYnpvSVZDdkJxb0hvCm5HcWdydVZqSVk5QU9wa3pia0ZVTWRUeDJ2ck5UQlRsbHNYdUlxSndtbS9sVWJ1blVCTWJhN2lKOHFaL2RINTkKUm9jaDRTVDBCU1pJR2xnV1k3YTdoNDRuT0g1TnlCbEgwcDNQZWUzb0VxeTl0ZUZrVXBWbURpYW1tY3BjWW1JdwpBSEFQb3NrMnlROGlSWGVCK0RKbWtQUXk1RWNTRy9ZQ1NSVUNKSXU0ei92Nnk0QUY0Y2ZRCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0="
    kube_config_raw        = "mock-kube-config"
    id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Instead, create a kubernetes_providers.tf file directly
generate "kubernetes_providers" {
  path      = "kubernetes_setup.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
# Variables for Kubernetes connection
variable "kubernetes_host" {
  description = "The Kubernetes cluster server host"
  type        = string
  sensitive   = true
}

variable "kubernetes_cluster_ca_certificate" {
  description = "The Kubernetes cluster CA certificate"
  type        = string
  sensitive   = true
}

# Provider configuration - no terraform block to avoid conflicts
provider "helm" {
  kubernetes {
    host                   = var.kubernetes_host
    cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
    
    # Use exec plugin for AAD authentication
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "kubelogin"
      args = [
        "get-token",
        "--login",
        "azurecli",
        "--server-id",
        "6dae42f8-4368-4678-94ff-3960e28e3630"
      ]
    }
  }
}

provider "kubernetes" {
  host                   = var.kubernetes_host
  cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)
  
  # Use exec plugin for AAD authentication
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "kubelogin"
    args = [
      "get-token",
      "--login",
      "azurecli",
      "--server-id",
      "6dae42f8-4368-4678-94ff-3960e28e3630"
    ]
  }
}
EOF
}

# Inputs for the Cilium module
inputs = {
  # Control whether to create Cilium resources
  create = true

  # AKS cluster details from the dependency
  cluster_name        = dependency.aks.outputs.name
  resource_group_name = dependency.aks.outputs.resource_group_name

  # Kubernetes configuration from the AKS cluster
  kubernetes_host                   = dependency.aks.outputs.host
  kubernetes_cluster_ca_certificate = dependency.aks.outputs.cluster_ca_certificate

  # Environment variables
  environment = local.env
  prefix      = local.prefix
  region_abbv = local.region_abbv

  # Cilium Helm chart version
  helm_chart_version = "1.17.2"

  # Enable TLS for Cilium - this fixes the TLS handshake errors
  # that were causing network issues for system pods
  tls = {
    enabled = true
  }

  # Enable debug mode to help diagnose TLS issues
  debug = {
    enabled = true
  }

  # Ensure proper CNI configuration
  cni = {
    chainingMode = "none"
    exclusive = true
  }

  # Use CRD identity allocation mode for better reliability and stability
  identityAllocationMode = "crd"

  # AKS BYOCNI Configuration - Enable AKS BYOCNI mode
  aksbyocni_enabled = true
  nodeinit_enabled  = true

  # Gateway API configuration
  gateway_api_enabled = false

  # Kube-proxy replacement - Using default "false" for compatibility
  kube_proxy_replacement = false

  # Service capabilities
  node_port_enabled    = true
  external_ips_enabled = true

  # CNI Socket LB configuration
  socket_lb_host_namespace_only = true

  # Disable Prometheus integration
  prometheus_enabled = false
  operator_prometheus_enabled = false

  # Disable Hubble
  hubble_enabled = false
  hubble_relay_enabled = false
  hubble_ui_enabled = false
  hubble_metrics_enabled = []
  hubble_metrics_enable_open_metrics = false

  # Resource limits for Cilium agent
  resources_limits_cpu      = "1000m"
  resources_limits_memory   = "1Gi"
  resources_requests_cpu    = "100m"
  resources_requests_memory = "128Mi"

  # Resource limits for Cilium operator
  operator_resources_limits_cpu      = "500m"
  operator_resources_limits_memory   = "512Mi"
  operator_resources_requests_cpu    = "50m"
  operator_resources_requests_memory = "64Mi"

  # Tags
  tags = merge(local.tags, {
    "component"      = "networking"
    "cilium-version" = "1.17.2"
    "managed-by"     = "terragrunt"
  })
} 