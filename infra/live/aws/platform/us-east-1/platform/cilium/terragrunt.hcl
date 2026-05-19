include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.cilium
}

dependency "eks" {
  config_path = "../eks"
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

        exec {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}"]
        }
      }
    }
  EOF
}

inputs = {
  create         = true
  cloud_provider = "aws"
  cluster_name   = dependency.eks.outputs.cluster_id

  k8s_service_host = replace(dependency.eks.outputs.cluster_endpoint, "https://", "")
  k8s_service_port = "443"

  helm_chart_version = include.base.locals.helm_versions.cilium
  helm_wait          = false

  tags = include.base.locals.tags
}
