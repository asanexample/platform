include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_otel_collector
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

dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The collector exports OTLP to Tempo's distributor — pull the endpoint from the tempo unit.
dependency "tempo" {
  config_path = "../tempo"

  mock_outputs = {
    otlp_grpc_endpoint = "http://tempo-distributor.observability.svc:4317"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "mimir" {
  config_path = "../mimir"

  mock_outputs = {
    push_endpoint = "http://mimir-gateway.observability.svc/api/v1/push"
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
  # Per-signal cost toggle (flip enable_trace_pipeline). create=false applies as a no-op.
  create    = include.base.locals.enable_trace_pipeline
  namespace = dependency.observability.outputs.namespace

  # OTLP/gRPC exporter wants host:port (no scheme) — strip http:// from the tempo output.
  tempo_otlp_endpoint = replace(dependency.tempo.outputs.otlp_grpc_endpoint, "http://", "")

  # OTLP metrics → Mimir (the hub's remote_write gateway). Lights up the metrics pipeline for OTEL-native
  # workloads (the activation operator + future ones); the X-Scope-OrgID tenant header is `platform` below.
  mimir_endpoint = dependency.mimir.outputs.push_endpoint

  # Tempo is multi-tenant (#628): stamp the hub's own traces (Beyla et al.) as tenant `platform`. Set this
  # BEFORE Tempo flips multitenancyEnabled so there's no rejection window (a single-tenant Tempo ignores it).
  tenant_id = "platform"

  helm_chart_version = include.base.locals.helm_versions.otel_collector
  helm_wait          = true

  # Sizing follows cost_profile (dev = 1 replica; prod = 2).
  high_availability = include.base.locals.high_availability

  tags = include.base.locals.tags
}
