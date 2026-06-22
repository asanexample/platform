include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.observability_cw_exporter
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

# Deploys into the shared observability namespace (Prometheus scrapes its ServiceMonitor). Depend on
# observability so the namespace exists first.
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
  # Cost-profile toggle (enable_cloud_metrics): off in dev, on for the platform cluster (env.hcl). create=false
  # applies as a no-op (empty state, skipped on teardown).
  create       = include.base.locals.enable_cloud_metrics
  cluster_name = dependency.eks.outputs.cluster_id
  aws_region   = include.base.locals.region

  namespace      = dependency.observability.outputs.namespace
  scrape_regions = [include.base.locals.region]

  # Identity = EKS Pod Identity (ADR-047): the module creates the CloudWatch-read role + association.

  helm_chart_version = include.base.locals.helm_versions.cloudwatch_exporter

  tags = include.base.locals.tags
}
