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
      secret_id = "preprod/tailscale/api-key"
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
      secret_id = "preprod/tailscale/oauth"
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

  # Preprod VPC CIDR — advertised to tailnet so VPN clients can reach private resources
  advertise_routes = ["10.101.0.0/16"]

  # Route DNS queries for these domains through VPC DNS resolver (AmazonProvidedDNS at VPC CIDR + 2).
  #
  # NB: `us-east-1.eks.amazonaws.com` is SHARED by both clusters' EKS endpoints, and `tailscale_dns_split_nameservers`
  # is tailnet-global keyed by domain — so platform + preprod were both writing this key (10.100.0.2 vs 10.101.0.2)
  # and last-writer-wins silently broke whichever lost. Point it at the PLATFORM resolver (10.100.0.2), which
  # resolves BOTH clusters' endpoints (platform directly + preprod via cross-vpc-dns), so the two units now agree
  # on a single correct value regardless of apply order. preprod-only hostnames keep the preprod resolver. (#206)
  split_dns = {
    "us-east-1.eks.amazonaws.com" = ["10.100.0.2"] # Shared EKS domain — platform resolver resolves both clusters
    "preprod.aws.refplat.org"     = ["10.101.0.2"] # Preprod-only service hostnames
  }

  helm_chart_version = include.base.locals.helm_versions.tailscale_operator

  tags = include.base.locals.tags
}
