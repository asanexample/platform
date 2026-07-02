include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_cortex_tenant
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

# Deploys into the shared observability namespace; forwards to the in-cluster Mimir gateway.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
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

inputs = {
  # P13 per-team re-tenant toggle (enable_per_team_tenants) — on for the platform hub (env.hcl). The
  # observability unit's Prometheus reroutes to this cortex-tenant once it's healthy (write_url output).
  create = include.base.locals.enable_per_team_tenants

  namespace = dependency.observability.outputs.namespace

  # Forward to the same in-cluster Mimir gateway push endpoint Prometheus writes to today.
  mimir_push_url = "http://mimir-gateway.observability.svc/api/v1/push"

  # Series with no team (all hub infra) → the platform tenant, never dropped.
  default_tenant = "platform"

  helm_chart_version = include.base.locals.helm_versions.cortex_tenant

  tags = include.base.locals.tags
}
