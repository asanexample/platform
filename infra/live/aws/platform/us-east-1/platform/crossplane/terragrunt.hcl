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

  # Agent control plane (ADR-082): the hub provisions platform AGENTS (XAgent) — hub-local platform infra —
  # NOT tenant Environments, so enable_environment_api stays OFF (ADR-048 holds). iam/eks mint the agent's
  # Pod-Identity role + association; provider-kubernetes (in-cluster) creates its ns/SA/obs-read RBAC; the
  # functions drive the Composition; enable_environment_provisioning supplies the scoped provisioner role +
  # the deny-escalation permissions boundary the agent's minted role is capped by.
  provider_services               = ["ecr", "iam", "eks"]
  enable_kubernetes_provider      = true
  kubernetes_provider_hostnetwork = true
  functions = [
    { name = "function-go-templating", package = "xpkg.upbound.io/crossplane-contrib/function-go-templating:v0.12.1" },
    { name = "function-auto-ready", package = "xpkg.upbound.io/crossplane-contrib/function-auto-ready:v0.6.5" },
    { name = "function-environment-configs", package = "xpkg.upbound.io/crossplane-contrib/function-environment-configs:v0.7.1" },
  ]
  enable_environment_provisioning = true
  management_account_id           = include.base.locals.account_ids["mgmt"]
  enable_agent_api                = true

  # Governance registry (ADR-089): install the WorkforceRole + Person CRDs on the hub so the activation
  # operator (and, as they grow, owner-routing / Backstage) can read the role catalog + workforce roster
  # locally. The records are projected by the argocd-apps `roles`/`people` apps; git stays the source.
  enable_governance_registry = true

  # Destroy-time CR finalizer cleanup auth (scripts/k8s-finalizer-clear.sh) — see crd_finalizer_cleanup.
  deployer_role_arn      = include.base.locals.deployer_role_arn
  finalizer_clear_script = "${get_repo_root()}/scripts/k8s-finalizer-clear.sh"

  tags = include.base.locals.tags
}
