include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_alloy
}

dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
    oidc_provider_arn             = "arn:aws:iam::000000000000:oidc-provider/mock"
    oidc_provider_url             = "oidc.eks.mock.amazonaws.com/id/mock"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The log collector deploys into the observability namespace (shared default-deny isolation) and ships to Loki.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "loki" {
  config_path = "../loki"

  mock_outputs = {
    push_endpoint = "http://loki-gateway.observability.svc/loki/api/v1/push"
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
  # Per-signal cost toggle (flip enable_log_pipeline). create=false applies as a no-op.
  create = include.base.locals.enable_log_pipeline

  namespace     = dependency.observability.outputs.namespace
  loki_push_url = dependency.loki.outputs.push_endpoint

  # P13 per-team log isolation (#590): derive each stream's Loki tenant from the pod `team` label. On the hub
  # there are no env namespaces, so everything falls back to the `platform` tenant (behaviour unchanged) —
  # this flip just proves the re-tenant River is valid before the preprod spoke, mirroring the metrics rollout.
  per_team_tenant = include.base.locals.enable_per_team_tenants

  emoji_log_annotations = true

  helm_chart_version = include.base.locals.helm_versions.alloy
  # DaemonSet on a capacity-tight cost-effective cluster: a node can be too packed to fit one pod,
  # which would (with atomic) roll back the whole release. Don't gate the apply on full scheduling —
  # verify readiness out-of-band (kubectl). atomic follows helm_wait in the module.
  helm_wait = false

  tags = include.base.locals.tags
}
