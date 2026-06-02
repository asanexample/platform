include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.crossplane
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

# Ordering only: Crossplane's rbac-manager authors wildcard provider ClusterRoles at runtime that the
# platform Kyverno (Enforce) restrict-wildcard-rbac policy would deny unless crossplane-system is excluded.
# The policy unit carries that exclusion (extra_exclude_principals/namespaces), so it must apply first.
dependency "policy" {
  config_path = "../policy"

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
  create = true

  cluster_name = dependency.eks.outputs.cluster_id
  region       = include.base.locals.region
  account_id   = include.base.locals.account_ids["platform"]

  helm_chart_version = include.base.locals.helm_versions.crossplane
  helm_wait          = true

  # P1: ECR only — proves reconciliation + drift correction with the smallest footprint. Later phases
  # extend provider_services (and the module's provisioning IAM policy) for the Tenant Composition.
  provider_services = ["ecr"]

  tags = include.base.locals.tags
}
