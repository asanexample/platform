include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_tenant_proxy
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

# Deploys into the shared observability namespace, next to Grafana + Mimir.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
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
  # P13 read-isolation toggle (enable_per_team_tenants) — on for the platform hub (env.hcl), where Grafana runs.
  create = include.base.locals.enable_per_team_tenants

  namespace = dependency.observability.outputs.namespace

  # Digest-pinned signed image (built + cosign-signed by tenant-proxy-image.yml → platform ECR). Bump this
  # digest to the build output and re-apply (ADR-071 digest-pin). Current: first build 2026-07-02.
  image = "829808296602.dkr.ecr.us-east-1.amazonaws.com/platform/tenant-proxy@sha256:9958c776c6ede1456e3340b356e1144934207884d49c7656edbd0d38f70584f0"

  # The per-team tenants populated by the cortex-tenant write side; admin (platform-admins) sees all.
  tenants     = ["alpha", "bravo", "platform"]
  admin_group = "platform-admins"

  tags = include.base.locals.tags
}
