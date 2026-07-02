include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.descheduler
}

# Descheduler (ADR-093) — periodically rebalances pods off over-utilized nodes onto under-utilized ones, so the
# post-unpark / post-Karpenter-consolidation node pile-up (one node ~99% CPU, another idle) self-corrects
# instead of crash-looping the hot node. Depends only on the cluster API.
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

# Order after node groups — which itself follows Cilium (BYOCNI: CNI before nodes) — so the cluster can
# actually schedule the descheduler pod and Cilium can hand it an IP before the helm wait. Ordering-only.
dependency "node_groups" {
  config_path = "../node-groups"

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
  cluster_name       = dependency.eks.outputs.cluster_id
  create             = true
  helm_chart_version = include.base.locals.helm_versions.descheduler
  helm_wait          = true

  # platform (hub) keeps the calm module defaults — underutilized 40% / overutilized 70%, every 15 min. It has
  # more and bigger nodes with conservative WhenEmpty consolidation (only reclaims empty nodes), so it's far
  # less imbalance-prone than preprod; and it runs stateful services (CNPG DBs, keycloak, backstage) where fewer
  # evictions is better (PDBs bound the churn regardless). Left explicit-by-omission; tune here if the hub grows
  # imbalance-prone.

  tags = include.base.locals.tags
}
