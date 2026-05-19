# Cilium CNI Deployment

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "${get_repo_root()}/infra/modules/cilium"
}

dependency "aks" {
  config_path  = "../aks_core"
  skip_outputs = false

  mock_outputs = {
    resource_group_name    = "mock-rg"
    name                   = "mock-aks"
    host                   = "https://mock-aks-api-server.hcp.westus.azmk8s.io:443"
    cluster_ca_certificate = "LS0tLS1CRUdJTi..."
    kube_config_raw        = "mock-kube-config"
    id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

generate "kubernetes_providers" {
  path      = "kubernetes_setup.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
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

provider "helm" {
  kubernetes {
    host                   = var.kubernetes_host
    cluster_ca_certificate = base64decode(var.kubernetes_cluster_ca_certificate)

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

inputs = {
  create = true

  cluster_name        = dependency.aks.outputs.name
  resource_group_name = dependency.aks.outputs.resource_group_name

  kubernetes_host                   = dependency.aks.outputs.host
  kubernetes_cluster_ca_certificate = dependency.aks.outputs.cluster_ca_certificate

  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  helm_chart_version = include.base.locals.helm_versions.cilium

  tls   = { enabled = true }
  debug = { enabled = true }
  cni   = { chainingMode = "none", exclusive = true }

  identityAllocationMode = "crd"

  cloud_provider = "azure"

  gateway_api_enabled    = false
  kube_proxy_replacement = false

  node_port_enabled             = true
  external_ips_enabled          = true
  socket_lb_host_namespace_only = true

  prometheus_enabled                 = false
  operator_prometheus_enabled        = false
  hubble_enabled                     = false
  hubble_relay_enabled               = false
  hubble_ui_enabled                  = false
  hubble_metrics_enabled             = []
  hubble_metrics_enable_open_metrics = false

  resources_limits_cpu      = "1000m"
  resources_limits_memory   = "1Gi"
  resources_requests_cpu    = "100m"
  resources_requests_memory = "128Mi"

  operator_resources_limits_cpu      = "500m"
  operator_resources_limits_memory   = "512Mi"
  operator_resources_requests_cpu    = "50m"
  operator_resources_requests_memory = "64Mi"

  tags = merge(include.base.locals.tags, {
    "component"      = "networking"
    "cilium-version" = include.base.locals.helm_versions.cilium
    "managed-by"     = "terragrunt"
  })
}
