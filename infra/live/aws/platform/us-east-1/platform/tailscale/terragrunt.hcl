include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.tailscale
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

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "external_secrets" {
  config_path = "../external-secrets"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
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
          args        = ["eks", "get-token", "--cluster-name", "${dependency.eks.outputs.cluster_id}", "--region", "${include.base.locals.region}", "--role-arn", "${include.base.locals.deployer_role_arn}"]
        }
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

generate "tailscale_provider" {
  path      = "tailscale-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "tailscale_api_key" {
      secret_id = "platform/tailscale/api-key"
    }

    provider "tailscale" {
      api_key = data.aws_secretsmanager_secret_version.tailscale_api_key.secret_string
      tailnet = "taild3190d.ts.net"
    }
  EOF
}

generate "oauth" {
  path      = "oauth.tf"
  if_exists = "overwrite"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "tailscale_oauth" {
      secret_id = "platform/tailscale/oauth"
    }

    locals {
      oauth_client_id     = jsondecode(data.aws_secretsmanager_secret_version.tailscale_oauth.secret_string)["clientId"]
      oauth_client_secret = jsondecode(data.aws_secretsmanager_secret_version.tailscale_oauth.secret_string)["clientSecret"]
    }
  EOF
}

inputs = {
  create       = true
  cluster_name = dependency.eks.outputs.cluster_id

  # Platform VPC CIDR — advertised to tailnet so VPN clients can reach private resources
  advertise_routes = ["10.100.0.0/16"]

  # Route DNS queries for these domains through VPC DNS resolver (AmazonProvidedDNS at VPC CIDR + 2)
  split_dns = {
    "us-east-1.eks.amazonaws.com" = ["10.100.0.2"] # Resolves private EKS API endpoints
    "aws.refplat.org"             = ["10.100.0.2"] # Resolves platform service hostnames
  }

  helm_chart_version = include.base.locals.helm_versions.tailscale_operator

  # Destroy-time finalizer cleanup auth (scripts/k8s-finalizer-clear.sh) — see the module's crd_finalizer_cleanup.
  region                 = include.base.locals.region
  deployer_role_arn      = include.base.locals.deployer_role_arn
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"

  tags = include.base.locals.tags
}
