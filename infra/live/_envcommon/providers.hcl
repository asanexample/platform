# ---------------------------------------------------------------------------------------------------------------------
# COMMON PROVIDER CONFIGURATIONS
# This file defines provider configurations that can be reused across multiple Terraform modules
# ---------------------------------------------------------------------------------------------------------------------

locals {
  # Extract cloud-specific configuration
  azure_config = {
    subscription_id = get_env("TF_VAR_azure_subscription_id", "db4f1d99-0ec0-44eb-90de-41975f9bb68b")
    tenant_id       = get_env("TF_VAR_azure_tenant_id", "c945e155-be68-4477-b8d7-01939adbfe55")
  }
  
  aws_config = {
    region = get_env("TF_VAR_aws_region", "us-east-1")
  }
  
  gcp_config = {
    project = get_env("TF_VAR_gcp_project_id", "your-gcp-project")
    region  = get_env("TF_VAR_gcp_region", "us-central1")
  }
}

# Azure provider configuration
generate "provider_azure" {
  path      = "provider_azure.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "azurerm" {
  features {}
  subscription_id = "${local.azure_config.subscription_id}"
  tenant_id       = "${local.azure_config.tenant_id}"
  use_cli         = true
}
EOF
}

# AWS provider configuration
generate "provider_aws" {
  path      = "provider_aws.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "aws" {
  region = "${local.aws_config.region}"
}
EOF
}

# GCP provider configuration
generate "provider_gcp" {
  path      = "provider_gcp.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<EOF
provider "google" {
  project = "${local.gcp_config.project}"
  region  = "${local.gcp_config.region}"
}
EOF
}

# Kubernetes provider configuration generator function
# This returns a provider block based on input parameters
# Usage: include this file and call the function in your module's terragrunt.hcl
k8s_provider_config = {
  generate_kubernetes_provider = {
    path      = "kubernetes_provider_override.tf"
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
  
  generate_helm_provider = {
    path      = "helm_provider_override.tf"
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
} 