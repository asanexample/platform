include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.argocd_apps
}

locals {
  teams_config = read_terragrunt_config("${get_repo_root()}/infra/live/aws/preprod/us-east-1/platform/teams.hcl")
  teams        = local.teams_config.locals.teams
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

dependency "argocd" {
  config_path = "../argocd"

  mock_outputs = {
    namespace = "argocd"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "argocd_clusters" {
  config_path = "../argocd-clusters"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "preprod_eks" {
  config_path = "../../../../preprod/us-east-1/platform/eks"

  mock_outputs = {
    cluster_endpoint = "https://mock-preprod-endpoint"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "github_token_secret" {
  path      = "github-token-secret.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "github_pat" {
      secret_id = "platform/github/argocd-pat"
    }

    resource "kubernetes_secret_v1" "github_appset_token" {
      metadata {
        name      = "github-appset-token"
        namespace = "argocd"
      }

      data = {
        token = data.aws_secretsmanager_secret_version.github_pat.secret_string
      }
    }
  EOF
}

generate "kubernetes_provider" {
  path      = "kubernetes-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    provider "kubernetes" {
      host                   = "${dependency.eks.outputs.cluster_endpoint}"
      cluster_ca_certificate = base64decode("${dependency.eks.outputs.cluster_certificate_authority}")

      exec {
        api_version = "client.authentication.k8s.io/v1beta1"
        command     = "aws"
        args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
      }
    }
  EOF
}

inputs = {
  create = true

  tenants = { for k, v in local.teams : k => {
    mode = v.mode
    apps = v.apps
  } }

  github_org               = "gangster"
  github_token_secret_name = "github-appset-token"
  ecr_registry             = "829808296602.dkr.ecr.us-east-1.amazonaws.com"
  preview_domain           = "preprod.aws.refplat.org"

  cluster_name     = "preprod"
  cluster_server   = dependency.preprod_eks.outputs.cluster_endpoint
  argocd_namespace = dependency.argocd.outputs.namespace
}
