include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.argocd_apps
}

locals {
  teams_config = read_terragrunt_config("${get_repo_root()}/infra/live/aws/preprod/us-east-1/platform/teams.hcl")
  teams        = local.teams_config.locals.teams

  # Tier-1/2 route aliases come from the XTenant claim (spec.domains, ADR-061) — the claim is the sole source,
  # NOT teams.hcl. Read each team's claim YAML and extract the declared hosts ([] when absent / no claim).
  claims_dir = "${get_repo_root()}/gitops/tenant-claims/preprod"
  team_domains = { for k, v in local.teams : k => (
    fileexists("${local.claims_dir}/${k}.yaml")
    ? try([for d in yamldecode(file("${local.claims_dir}/${k}.yaml")).spec.domains : d.host], [])
    : []
  ) }
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

dependency "argocd" {
  config_path = "../argocd"

  mock_outputs = {
    namespace = "argocd"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "argocd_clusters" {
  config_path = "../argocd-clusters"

  mock_outputs                            = {}
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

dependency "preprod_eks" {
  config_path = "../../../../preprod/us-east-1/platform/eks"

  mock_outputs = {
    cluster_endpoint = "https://mock-preprod-endpoint"
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

generate "github_token_secret" {
  path      = "github-token-secret.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "github_pat" {
      secret_id = "platform/github/argocd-pat"
    }

    resource "kubernetes_secret_v1" "github_appset_token" {
      metadata {
        name      = "github-appset-token"
        namespace = "argocd"
      }

      data = {
        token = data.aws_secretsmanager_secret_version.github_pat.secret_string
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
  create = true

  tenants = { for k, v in local.teams : k => {
    mode    = v.mode
    domains = local.team_domains[k]
    apps    = v.apps
  } }

  github_org               = "asanexample"
  github_token_secret_name = "github-appset-token"                                                                                # K8s secret created by generate block above
  ecr_registry             = "${include.base.locals.account_ids["platform"]}.dkr.ecr.${include.base.locals.region}.amazonaws.com" # Platform account ECR
  preview_domain           = "preprod.aws.refplat.org"

  # Target cluster name in ArgoCD — the preprod cluster that ArgoCD manages,
  # not the platform cluster where ArgoCD runs
  cluster_name     = "preprod"
  cluster_server   = dependency.preprod_eks.outputs.cluster_endpoint
  argocd_namespace = dependency.argocd.outputs.namespace

  # Git-native Team delivery via ArgoCD (ADR-063): sync the cluster-scoped Team CRs from the platform repo to
  # preprod (replaces the crossplane-teams Helm projection — the crossplane unit now passes teams = {}). The
  # Team CRs are admission inputs for Kyverno's envelope/team-must-exist, so this app carries a sync-wave ahead
  # of tenant-claims.
  enable_teams      = true
  teams_repo_url    = "https://github.com/asanexample/platform"
  teams_repo_branch = "main"
  teams_repo_path   = "gitops/teams"

  # Tenant-claim delivery via ArgoCD (BACK stack Phase 1): sync the cluster-scoped XTenant claim YAMLs from
  # the platform repo to preprod (replaces the tenant-claims Terragrunt unit). The argocd unit excludes the
  # XTenant XR from selfHeal drift; the policy unit excludes ArgoCD's assumed-role from the S1 backstop.
  enable_tenant_claims      = true
  tenant_claims_repo_url    = "https://github.com/asanexample/platform"
  tenant_claims_repo_branch = "main"
  tenant_claims_repo_path   = "gitops/tenant-claims/preprod"
}
