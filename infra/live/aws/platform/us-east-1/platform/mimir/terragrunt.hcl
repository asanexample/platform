include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_mimir
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

# Mimir deploys into the observability namespace (shares Grafana's datasource sidecar + the
# default-deny NetworkPolicy isolation). Depend on observability so the namespace exists first.
dependency "observability" {
  config_path = "../observability"

  mock_outputs = {
    namespace = "observability"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Shared Cilium Gateway — Mimir self-routes its cross-cluster spoke-ingest HTTPRoute onto it (P10),
# the same self-routing pattern keycloak uses (ADR-059). Gateway is EARLY in the DAG (no app deps).
dependency "gateway" {
  config_path = "../gateway"

  mock_outputs = {
    gateway_name      = "platform-gateway"
    gateway_namespace = "default"
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
  # Cost-profile toggle: off in dev (Prometheus-only, no durable long-range store). Flip enable_mimir in
  # common.hcl to deploy it. create=false applies as a no-op (empty state, skipped on teardown).
  create       = include.base.locals.enable_mimir
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  # Clean `cluster` label on Mimir's own self-metrics (#630) — the env name, matching the hub's
  # Prometheus externalLabels.cluster, not the chart default (release name "mimir").
  cluster_label = include.base.locals.env

  namespace = dependency.observability.outputs.namespace

  oidc_provider_arn = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url = dependency.eks.outputs.oidc_provider_url

  helm_chart_version = include.base.locals.helm_versions.mimir
  helm_wait          = true

  # Sizing follows cost_profile (dev = single-replica minimal; prod = RF3 + zone-aware).
  high_availability = include.base.locals.high_availability
  storage_class     = "gp3"

  # Mimir is Grafana's default datasource (durable, full-range); the observability change sets the bundled
  # Prometheus datasource non-default so there's exactly one default.
  datasource_is_default = true

  # Cross-cluster spoke ingest (P10): self-route a write-only, tenant-overwriting HTTPRoute per spoke onto
  # the shared Gateway, and surface each spoke's tenant as its own Grafana datasource. preprod is the first
  # spoke; add a `<prefix> = <tenant>` entry (and the matching datasource) to onboard the next one.
  spoke_ingest = {
    domain            = "aws.refplat.org"
    gateway_name      = dependency.gateway.outputs.gateway_name
    gateway_namespace = dependency.gateway.outputs.gateway_namespace
    tenants           = { preprod = "preprod" }
  }
  extra_tenant_datasources = ["preprod"]

  # Multi-cluster single pane (#626): enable read-path tenant federation + a `Mimir (all clusters)`
  # datasource spanning platform|preprod. Platform-admin overview lane (per-team scoping = P13).
  enable_federated_datasource = true

  tags = include.base.locals.tags
}
