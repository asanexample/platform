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

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "kubeconfig" {
  path      = "kubeconfig.yaml"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        server: ${dependency.eks.outputs.cluster_endpoint}
        certificate-authority-data: ${dependency.eks.outputs.cluster_certificate_authority}
      name: default
    contexts:
    - context:
        cluster: default
        user: default
      name: default
    current-context: default
    users:
    - name: default
      user:
        exec:
          apiVersion: client.authentication.k8s.io/v1beta1
          command: aws
          args:
          - eks
          - get-token
          - --cluster-name
          - ${dependency.eks.outputs.cluster_id}
          - --region
          - ${include.base.locals.region}
          - --role-arn
          - arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole
  EOF
}

generate "helm_provider" {
  path      = "helm-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "helm" {
      kubernetes = {
        host                   = "${dependency.eks.outputs.cluster_endpoint}"
        cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

        exec = {
          api_version = "client.authentication.k8s.io/v1beta1"
          command     = "aws"
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "arn:aws:iam::${include.base.locals.account_id}:role/OrganizationAccountAccessRole"]
        }
      }
    }
  EOF
}

inputs = {
  create          = true
  cloud_provider  = "aws"
  cluster_name    = dependency.eks.outputs.cluster_id
  kubeconfig_path = "kubeconfig.yaml"

  k8s_service_host = replace(dependency.eks.outputs.cluster_endpoint, "https://", "")
  k8s_service_port = "443"

  helm_chart_version = include.base.locals.helm_versions.cilium
  helm_wait          = false

  tags = include.base.locals.tags
}
