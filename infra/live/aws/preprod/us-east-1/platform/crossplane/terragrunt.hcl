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
# preprod Kyverno (Enforce) restrict-wildcard-rbac policy would deny unless crossplane-system is excluded.
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
  account_id   = include.base.locals.account_id # preprod — unused until AWS providers land (P2b)

  helm_chart_version = include.base.locals.helm_versions.crossplane
  helm_wait          = true

  # P2a (federated tenant control plane, ADR-048): the Tenant API + the K8s footprint only. No AWS providers
  # yet — the Pod-team IAM role, Pod Identity association, and cross-account ECR arrive in P2b.
  provider_services = []

  enable_kubernetes_provider      = true
  kubernetes_provider_hostnetwork = true # Object CRD is multi-version → its conversion webhook must be reachable (overlay)

  functions = [
    { name = "function-go-templating", package = "xpkg.upbound.io/crossplane-contrib/function-go-templating:v0.12.1" },
    { name = "function-auto-ready", package = "xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.6.5" },
  ]

  enable_tenant_api = true

  tags = include.base.locals.tags
}
