/**
 * # ArgoCD Bootstrap Configuration
 *
 * This Terragrunt configuration deploys bootstrap applications on ArgoCD in the `ops/westus` environment.
 */

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root terragrunt.hcl configuration
include "root" {
  path = find_in_parent_folders()
}

# Define dependencies - this bootstrap module depends on ArgoCD and AKS
dependencies {
  paths = ["../argocd", "../aks_core"]
}

# Define specific dependency on ArgoCD for namespace info
dependency "argocd" {
  config_path = "../argocd"

  # Mock outputs for plan and validation
  mock_outputs = {
    namespace = "argocd"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Define specific dependency on AKS cluster for Kubernetes configuration
dependency "aks" {
  config_path = "../aks_core"

  # Wait for the AKS cluster to be fully deployed
  skip_outputs = false

  # Mock outputs for plan and validation
  mock_outputs = {
    resource_group_name    = "mock-rg"
    name                   = "mock-aks"
    host                   = "https://mock-aks-api-server.hcp.westus.azmk8s.io:443"
    cluster_ca_certificate = "LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0tCk1JSUVMVENDQXBXZ0F3SUJBZ0lSQU1lTmFXNzVKUCttREcvWXJVaXZKR2t3RFFZSktvWklodmNOQVFFTEJRQXcKRFRFTE1Ba0dBMVVFQXhNQ1kyRXdJQmNOTWpRd016STJNREV3TVRJNVdoZ1BNakExTkRBek1qWXdNVEV4TWpsYQpNQTB4Q3pBSkJnTlZCQU1UQW1OaE1JSUNJakFOQmdrcWhraUc5dzBCQVFFRkFBT0NBZzhBTUlJQ0NnS0NBZ0VBCnE2WTJ5SUI2NHpkdXpFdk1PSjM2dURPM3ExRGFrTmdyaFRFNHpLaFc2QjJZeUVpSW4rcWVFVVVxUll0RkNka3oKTzJYeUlKVGg1RVVSc0NCdTlrWm82QW9CczgrYmFLN0xnSXFnZ2RjQU56Zmp0MXVIRkZ4TnJ2Y1pDNElhdm13UwpRem9HdlkwZFgwQnZTcFprbUx0TVhxZDdTekVIOUpPVEpQRlJBQ0d6WVVES3VxVXptZ0czaDlUY2s3cHBTNm0vCmttSlNTWldHYnd5OVJxRXQzZk1BZlJINGtnVDRxZFZZMjR0NjdCRkxlNDduTWJQTStEbGttUWJWVUFhNE85UU0KZnE2RVJpZUlUdk0xVzhLZWhQblNHUUFKbWRQM1lheVZtL3djbS9lbTBVRmYzWStzWUNQcmYveGRJNHdyQXdzbwpzSE1Pcm9kS29EUmJjNFU2TFNZTVZKRVlTTHQvUS9PazAyMkVlNlkwVUJEOUc5NXgraE9oRERPZUZjWi9LYlJJCjZxSGxGU0ZSa3o1Qy9HeVJvbUhFbk5iQnhOb3A4ZVZsVXB0ZGdBYnNBRmZNMExCTFlzZ2NtRndORERud2NkdTEKZFF1V294SVV0S2dUL2lkbzY2NEpqYXhuMWs5Z3kvMlRVY3BQZ0k0bGFnMCtYRFJROW5YbURIV3BKUmZXeERVagpCcE9ZczRQRGpBd3hpeFJHWnVtbXA0MlNtRS9VRUhIQnRua3Bid2NiWExzMzkwVFRLdmtHL2tKSWsvL2pWYW1OCmI3L0RvZW5GY1ArdzRjL21MZ1M5aTFpYnRQMkZoNWNLcmRXWGdKWmVnVE1GOXZNZXRCKzJnTUhaUU9QbVdQaCsKS2NMcnlvMVNqNnVqdVE1UkM0OXY2UkExRFZFM3BsR0x2cDlvd2ZzQ0F3RUFBYU5DTUVBd0RnWURWUjBQQVFILwpCQVFEQWdJRU1BOEdBMVVkRXdFQi93UUZNQU1CQWY4d0hRWURWUjBPQkJZRUZJaXpZZ1NRbnRHNXEzb0JVK2taCnozWURYT0NRTUEwR0NTcUdTSWIzRFFFQkN3VUFBNElCQVFDSTFJaGdWU3I3VWs2a0FwMWpKRmE0LzFENkswaisKOGE1TG5pUHVNS1lOeWFibU9GNDVueUoyWXZZYmRMd1VYKy8wVVVyRVVnOHQvL3ZyYnFNMjgxbHlob0lZdEpLWApYM0dpWEFzQ2xBZWdQNTdtNEQ1TWJtZFgxL0FLbjVxcmJtbjZmRWRaZzJNdDdmTWRBeTRzYnpvSVZDdkJxb0hvCm5HcWdydVZqSVk5QU9wa3pia0ZVTWRUeDJ2ck5UQlRsbHNYdUlxSndtbS9sVWJ1blVCTWJhN2lKOHFaL2RINTkKUm9jaDRTVDBCU1pJR2xnV1k3YTdoNDRuT0g1TnlCbEgwcDNQZWUzb0VxeTl0ZUZrVXBWbURpYW1tY3BjWW1JdwpBSEFQb3NrMnlROGlSWGVCK0RKbWtQUXk1RWNTRy9ZQ1NSVUNKSXU0ei92Nnk0QUY0Y2ZRCi0tLS0tRU5EIENFUlRJRklDQVRFLS0tLS0="
    kube_config_raw        = "mock-kube-config"
    id                     = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/mock-rg/providers/Microsoft.ContainerService/managedClusters/mock-aks"
  }
  mock_outputs_allowed_terraform_commands = ["validate", "plan"]
}

# Generate Kubernetes provider configuration
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

# Generate versions.tf for required providers
generate "versions_override" {
  path      = "versions.tf"
  if_exists = "overwrite"
  contents  = <<EOF
terraform {
  required_version = ">= 1.0.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10.0"
    }
    null = {
      source  = "hashicorp/null"
      version = ">= 3.1.0"
    }
  }
}
EOF
}

# Use the centralized module for bootstrap implementation
terraform {
  source = "../../../../../modules/argocd-bootstrap"
}

# Inputs for the bootstrap module
inputs = {
  # ArgoCD namespace from the ArgoCD module
  argocd_namespace = dependency.argocd.outputs.namespace

  # Kubernetes configuration from AKS
  kubernetes_host                   = dependency.aks.outputs.host
  kubernetes_cluster_ca_certificate = dependency.aks.outputs.cluster_ca_certificate

  # Configuration for Application CR
  project = "default"
  server  = "https://kubernetes.default.svc"

  # Bootstrap applications
  bootstrap_applications = [
    {
      name            = "cert-manager-${include.base.locals.env}-${include.base.locals.region_abbv}"
      namespace       = "cert-manager"
      repo_url        = "https://charts.jetstack.io"
      chart           = "cert-manager"
      target_revision = "v1.12.0"
      sync_wave       = 0
      helm_values = {
        "installCRDs" = "true"
      }
    },
    {
      name            = "external-dns-${include.base.locals.env}-${include.base.locals.region_abbv}"
      namespace       = "external-dns"
      repo_url        = "https://kubernetes-sigs.github.io/external-dns"
      chart           = "external-dns"
      target_revision = "1.13.1"
      sync_wave       = 1
    },
    {
      name            = "external-secrets-${include.base.locals.env}-${include.base.locals.region_abbv}"
      namespace       = "external-secrets"
      repo_url        = "https://charts.external-secrets.io"
      chart           = "external-secrets"
      target_revision = "0.9.5"
      sync_wave       = 1
    }
  ]
}
