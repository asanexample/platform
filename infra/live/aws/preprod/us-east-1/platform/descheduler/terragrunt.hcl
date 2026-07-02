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

# Descheduler (ADR-093) — periodically rebalances pods off over-utilized nodes onto under-utilized ones. On
# preprod this is what stops the post-unpark / post-consolidation pile-up where one small node lands ~99% CPU
# (crash-looping its own kubelet + Karpenter) while another sits idle. Depends only on the cluster API.
dependency "eks" {
  config_path = "../eks"

  mock_outputs = {
    cluster_id                    = "mock-cluster"
    cluster_endpoint              = "https://mock-endpoint"
    cluster_certificate_authority = "bW9jaw=="
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
  cluster_name       = dependency.eks.outputs.cluster_id
  create             = true
  helm_chart_version = include.base.locals.helm_versions.descheduler
  helm_wait          = true

  # preprod is small (1-2 t4g.large) and the most imbalance-prone: aggressive WhenEmptyOrUnderutilized
  # consolidation + staggered post-unpark node bring-up. Two adjustments off the module defaults:
  #  - Raise the DESTINATION (underutilized) threshold to 50%. LowNodeUtilization only rebalances if some node
  #    is below ALL thresholds; the 2026-07-02 incident's cool node sat at 39% CPU — one percent under the 40%
  #    default. 50% gives the emptier of two small nodes reliable headroom to qualify as a rebalance target.
  #  - Faster cadence (10 min): churn is cheap on non-prod, and this is where a hot node melts down.
  # Overutilized stays 70% — catches the ~99% incident with wide margin, well under the kubelet-degradation zone.
  schedule                 = "*/10 * * * *"
  underutilized_thresholds = { cpu = 50, memory = 50, pods = 50 }
  overutilized_thresholds  = { cpu = 70, memory = 70, pods = 70 }

  tags = include.base.locals.tags
}
