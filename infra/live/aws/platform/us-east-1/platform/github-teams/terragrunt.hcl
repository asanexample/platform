include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.github_teams
}

# ---------------------------------------------------------------------------
# Derive teams + repo ownership from the git registries (ADR-072 Flavor A)
# ---------------------------------------------------------------------------
# A team is materialised in GitHub on Team-CR convergence — the same registry-derived, apply-on-merge pattern
# as its Keycloak group (keycloak-config) and its per-Product OIDC role (github-oidc). NOT imperatively from the
# scaffolder: "create a team → it appears in every external system" stays uniform across Keycloak + GitHub.
locals {
  teams_dir = "${get_repo_root()}/gitops/teams"
  teams = { for f in fileset(local.teams_dir, "*.yaml") :
    yamldecode(file("${local.teams_dir}/${f}")).metadata.name => {}
  }

  # One push grant per Product (gitops/products/<team>/<product>.yaml), keyed by the bare repo name (the
  # <team>-<product> half of spec.repo "asanexample/<team>-<product>" — org-unique by construction, ADR-072).
  # fileset returns [] when no Products exist yet, so this is empty on a clean platform.
  products_dir = "${get_repo_root()}/gitops/products"
  repo_grants = { for f in fileset(local.products_dir, "**/*.yaml") :
    split("/", yamldecode(file("${local.products_dir}/${f}")).spec.repo)[1] => {
      team = yamldecode(file("${local.products_dir}/${f}")).spec.team
      repo = split("/", yamldecode(file("${local.products_dir}/${f}")).spec.repo)[1]
    }
  }
}

# The github provider authenticates as the dedicated platform-github-ownership App (Members: write +
# Administration: write, org-wide), creds in Secrets Manager (platform/github-ownership/app — a JSON
# {app_id, installation_id, pem}). One-time manual prereq: docs/runbooks/github-ownership-app.md. The aws
# provider (for the data source) comes from root.hcl.
generate "github_provider" {
  path      = "github-provider.tf"
  if_exists = "overwrite_terragrunt"
  contents  = <<-EOF
    data "aws_secretsmanager_secret_version" "gh_ownership_app" {
      secret_id = "platform/github-ownership/app"
    }

    locals {
      gh_app = jsondecode(data.aws_secretsmanager_secret_version.gh_ownership_app.secret_string)
    }

    provider "github" {
      owner = "asanexample"
      app_auth {
        id              = local.gh_app.app_id
        installation_id = local.gh_app.installation_id
        pem_file        = local.gh_app.pem
      }
    }
  EOF
}

inputs = {
  create      = true
  teams       = local.teams
  repo_grants = local.repo_grants
}
