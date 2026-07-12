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
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "node_groups" {
  config_path = "../node-groups"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# The metrics spoke owns the preprod `observability` namespace. Order after it so the namespace exists.
dependency "observability_spoke" {
  config_path = "../observability-spoke"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Traces ship over the Transit Gateway to the platform hub. Order after the TGW spoke attachment.
dependency "transit_gateway" {
  config_path = "../transit-gateway"

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
  create    = true
  namespace = dependency.observability_spoke.outputs.namespace

  # Spoke collector: preprod workloads send OTLP here (once instrumented — P7); it forwards over the TGW to
  # the platform hub's Tempo spoke-ingest edge via OTLP/HTTP. The hub Gateway force-sets X-Scope-OrgID=preprod
  # (write-only); the resource processor stamps cluster=preprod so the hub isolates/breaks out by cluster.
  tempo_otlp_endpoint   = "https://preprod-traces.aws.refplat.org"
  exporter_use_http     = true
  exporter_tls_insecure = false
  tenant_id             = "preprod" # belt-and-suspenders; the edge overwrites it
  resource_attributes   = { cluster = "preprod" }

  # Metrics spoke (P10/P14): forward tenant app-SDK OTLP metrics to the hub Mimir's OTLP ingest over the TGW,
  # via the same `preprod-mimir` gateway edge (which force-sets X-Scope-OrgID=preprod, write-only). Without
  # this the collector's metrics pipeline exports to `debug` (dropped) and tenant RED metrics never reach
  # Mimir — the ADR-056 canary metric-gate and the per-Product shop dashboards then have no data. The hub's
  # /otlp/v1/metrics spoke route is added in the platform `mimir` unit.
  mimir_endpoint = "https://preprod-mimir.aws.refplat.org/otlp/v1/metrics"

  helm_chart_version = include.base.locals.helm_versions.otel_collector
  helm_wait          = true

  tags = include.base.locals.tags
}
