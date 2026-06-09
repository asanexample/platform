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
  # Claim-as-single-source (ADR-061): app delivery is derived entirely from the XTenant claim YAMLs — apps
  # (repo/repoPath/preview) and the tier-1/2 route aliases (spec.domains). Replaces the retired teams.hcl.
  # Key each claim by spec.team; one tenant per team today (namespace isolation, ADR-033).
  claims_dir = "${get_repo_root()}/gitops/tenant-claims/preprod"
  claims = { for f in fileset(local.claims_dir, "*.yaml") :
    yamldecode(file("${local.claims_dir}/${f}")).spec.team => yamldecode(file("${local.claims_dir}/${f}"))
  }
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

  tenants = { for team, claim in local.claims : team => {
    mode        = "namespace" # namespace isolation only; vCluster deferred (ADR-033)
    environment = claim.spec.environment
    # v2 namespace = <team>-<name>-<env> (matches Composition v2); overrides the module's team-<team> default.
    namespace = "${team}-${claim.spec.name}-${claim.spec.environment}"
    domains   = try([for d in claim.spec.domains : d.host], [])
    apps = { for app, cfg in claim.spec.apps : app => {
      repo_url  = "https://github.com/${cfg.repo}"
      repo_path = try(cfg.repoPath, "k8s/preprod")
      preview   = try(cfg.preview, false)
    } }
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
