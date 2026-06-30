include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_opencost
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

# Ordering only — OpenCost deploys into the spoke's observability namespace and its ServiceMonitor is scraped by
# the spoke prometheus-agent (which selects all ServiceMonitors) → shipped to the hub Mimir's `preprod` tenant.
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

# Required even though create_dashboard=false here (the count=0 ConfigMap resource still needs the provider).
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
  # Cost-profile toggle (enable_cost_metrics): turned on for preprod in env.hcl (ADR-091) so tenant-environment
  # cost is measured where the workloads run (the spoke).
  create = include.base.locals.enable_cost_metrics

  namespace = "observability"

  # Spoke has no in-cluster queryable Prometheus (agent-only) — point OpenCost at the hub Mimir's query API via
  # its external ingress (the same host the agent writes to; the ingress injects the `preprod` tenant by
  # hostname, so no header is needed). The dashboard reads OpenCost's EXPORTER metrics, so this query path is
  # only for the allocation API; exporter metrics flow regardless.
  prometheus_external_url = "https://preprod-mimir.aws.refplat.org/prometheus"

  # No Grafana on the spoke — only emit metrics; the hub dashboard (federated `mimir-all` datasource) renders them.
  create_dashboard = false

  # Budget enforcement (ADR-091 Phase C): the hourly annotator writes over-budget teams to cost-budget-status
  # (read by the Kyverno policy in the policy unit). Runs here — the Team CRs + Mimir egress + OpenCost are here.
  enable_budget_enforcer = true

  helm_chart_version = include.base.locals.helm_versions.opencost

  tags = include.base.locals.tags
}
