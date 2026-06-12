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
  # v3 delivery (ADR-067/069 §1, L2b #384): per-Product delivery derives from the git-native Product registry
  # (gitops/products/<team>/<product>.yaml) — the sole source replacing the retired v2 XTenant claims. One
  # ApplicationSet per product; the per-Environment fan-out reads gitops/environments/<team>/<product>/*.yaml.
  # metadata.name = <team>-<product> (e.g. alpha-demo); spec.{team,repo} drive the Application source.
  products_dir = "${get_repo_root()}/gitops/products"
  products = { for f in fileset(local.products_dir, "**/*.yaml") :
    yamldecode(file("${local.products_dir}/${f}")).metadata.name => {
      team     = yamldecode(file("${local.products_dir}/${f}")).spec.team
      product  = trimprefix(yamldecode(file("${local.products_dir}/${f}")).metadata.name, "${yamldecode(file("${local.products_dir}/${f}")).spec.team}-")
      repo_url = "https://github.com/${yamldecode(file("${local.products_dir}/${f}")).spec.repo}"
    }
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

  # v2 XTenant-claim delivery is RETIRED at the cutover (ADR-067/069) — the per-Product ApplicationSets below
  # (products) replace it. Empty disables the legacy `tenants` Applications in the module.
  tenants = {}

  # v3 per-Product delivery: one ApplicationSet per product, fanning out over the product's Environment claims
  # (gitops/environments/<team>/<product>/*.yaml) → one Application per Environment. Derived from gitops/products.
  products = local.products

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

  # v3 cutover (ADR-067/069): the v2 XTenant claim sync is retired (enable_tenant_claims=false) and replaced by
  # the v3 delivery surface, activated by platform_repo_url: the registry-sync apps (project gitops/products +
  # gitops/environments → cluster CRs, sync-wave -2/0) AND the per-Product ApplicationSet (delivers each app's
  # k8s/overlays/<stage>, injecting ns + host). Teams still sync via enable_teams above.
  enable_tenant_claims = false

  platform_repo_url    = "https://github.com/asanexample/platform"
  platform_repo_branch = "main"
}
