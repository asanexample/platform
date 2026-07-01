include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_policy_reporter
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

# Ordering only — policy-reporter deploys into the spoke's observability namespace and its ServiceMonitor is
# scraped by the spoke prometheus-agent (which selects all ServiceMonitors) → shipped to the hub Mimir's
# `preprod` tenant.
dependency "observability_spoke" {
  config_path = "../observability-spoke"

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

inputs = {
  # Policy-reporting toggle (enable_policy_reporting): on for preprod (env.hcl) — this is where the tenant
  # environments (Kyverno Enforce) actually live, so this is where the PolicyReport volume is (#93 P12).
  create = include.base.locals.enable_policy_reporting

  namespace = "observability"

  # No Grafana on the spoke — only emit metrics; the hub dashboards (federated `mimir-all` datasource) render
  # them, same split as OpenCost.
  create_dashboards = false

  helm_chart_version = include.base.locals.helm_versions.policy_reporter

  tags = include.base.locals.tags
}
