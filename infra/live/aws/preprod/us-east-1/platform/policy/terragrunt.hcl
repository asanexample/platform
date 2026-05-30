include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.policy
}

locals {
  teams_config = read_terragrunt_config("${get_terragrunt_dir()}/../teams.hcl")
  teams        = local.teams_config.locals.teams

  # Tenant images live in the platform account's ECR (apps push there — see #60).
  ecr_registry = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com"
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

  # Enforce: reject violations at admission (webhook fails closed). Flipped after the Audit phase
  # confirmed PolicyReports clean against the live alpha workload (ADR-014 rollout).
  validation_failure_action = "Enforce"

  compliance_tier = include.base.locals.compliance_tier
  replica_count   = 1 # non-prod; platform runs 3 for HA

  # Cluster-wide tenant image floor + per-team scoping (team data stays at the unit level).
  allowed_registries  = [local.ecr_registry]
  tenant_registry_map = { for k, v in local.teams : k => "${local.ecr_registry}/team-${k}" }

  helm_chart_version = include.base.locals.helm_versions.kyverno
  helm_wait          = true

  # Phase 3 — cosign keyless image verification (Audit-first, independent of the Enforce above).
  enable_image_verification = true
  verify_failure_action     = "Enforce"
  oidc_provider_arn         = dependency.eks.outputs.oidc_provider_arn
  oidc_provider_url         = dependency.eks.outputs.oidc_provider_url
  ecr_account_id            = include.base.locals.account_ids["platform"]
  # Per-team cosign keyless identities derived from each team's app repo (team data stays at the unit).
  verify_subjects = { for k, v in local.teams : k => {
    deploy_subject         = "${values(v.apps)[0].repo_url}/.github/workflows/deploy.yml@refs/heads/main"
    preview_subject_regexp = "${values(v.apps)[0].repo_url}/.github/workflows/preview.yml@refs/.*"
  } }

  tags = include.base.locals.tags
}
