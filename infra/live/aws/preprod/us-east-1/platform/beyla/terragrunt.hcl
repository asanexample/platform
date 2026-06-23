include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_beyla
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

# Beyla (eBPF, privileged PSA) runs in the shared observability namespace owned by the metrics spoke, and
# exports traces to the preprod traces-spoke OTel collector there. Order after both.
dependency "observability_spoke" {
  config_path = "../observability-spoke"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "traces_spoke" {
  config_path = "../observability-traces-spoke"

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
  # Cost-profile toggle (enable_instrumentation): on for preprod (env.hcl) so its apps are instrumented.
  create = include.base.locals.enable_instrumentation

  namespace = dependency.observability_spoke.outputs.namespace

  # Dogfood on the preprod app/environment namespaces (the alpha demo products) — real workloads, real
  # HTTP traffic → RED + traces with zero code change. (The hub instruments its own platform services.)
  instrument_namespaces = "{alpha-*}"

  # otel_traces_endpoint defaults to otel-collector.observability.svc:4317 — which IS the preprod traces-spoke
  # collector (same name/namespace). It stamps cluster=preprod and forwards to the hub Tempo edge.

  helm_chart_version = include.base.locals.helm_versions.beyla

  tags = include.base.locals.tags
}
