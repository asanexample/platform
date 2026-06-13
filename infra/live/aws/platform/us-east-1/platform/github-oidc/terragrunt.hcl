include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.github_oidc
}

dependency "ecr" {
  config_path = "../ecr"

  mock_outputs = {
    repository_arns = {
      "team-alpha/demo"     = "arn:aws:ecr:us-east-1:000000000000:repository/team-alpha/demo"
      "team-bravo/demo"     = "arn:aws:ecr:us-east-1:000000000000:repository/team-bravo/demo"
      "platform/backstage"  = "arn:aws:ecr:us-east-1:000000000000:repository/platform/backstage"
      "platform/gha-runner" = "arn:aws:ecr:us-east-1:000000000000:repository/platform/gha-runner"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

locals {
  # ---------------------------------------------------------------------------
  # One OIDC ECR-push role per PRODUCT, derived from the Product registry
  # (gitops/products/<team>/<product>.yaml — see product_roles below): each role trusts only the Product's repo
  # and pushes only to its product-scoped ECR (team-<team>/<product>-*). ADR-069 §5.
  # ---------------------------------------------------------------------------
  products_dir = "${get_repo_root()}/gitops/products"
  products = {
    for f in fileset(local.products_dir, "**/*.yaml") :
    yamldecode(file("${local.products_dir}/${f}")).metadata.name => {
      team    = yamldecode(file("${local.products_dir}/${f}")).spec.team
      product = trimsuffix(basename(f), ".yaml") # short name (the filename) = the gitops/.../<product>.yaml stem
      repo    = yamldecode(file("${local.products_dir}/${f}")).spec.repo
    }
  }
  product_roles = { for key, p in local.products :
    "github-actions-ecr-push-product-${key}" => {
      repos    = [split("/", p.repo)[1]] # the Product's repo (one repo : one product)
      branches = ["main", "refs/tags/*"] # main + release tags
      events   = ["pull_request"]        # + PR preview builds (preview = true)
      tags     = { Team = p.team, Product = p.product }
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          { Sid = "ECRAuth", Effect = "Allow", Action = ["ecr:GetAuthorizationToken"], Resource = "*" },
          {
            Sid    = "ECRPush"
            Effect = "Allow"
            Action = [
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "ecr:PutImage",
              "ecr:InitiateLayerUpload",
              "ecr:UploadLayerPart",
              "ecr:CompleteLayerUpload",
            ]
            # Only this product's repos (team-<team>/<product>-*), Composition-created. Wildcard by construction.
            Resource = ["arn:aws:ecr:${include.base.locals.region}:${include.base.locals.account_id}:repository/team-${p.team}/${p.product}-*"]
          },
        ]
      })
    }
  }
}

inputs = {
  create     = true
  github_org = "asanexample"

  # Image-build OIDC ECR-push roles: the platform infra roles (Backstage, the ARC runner) + the per-Product
  # roles (local.product_roles, ADR-069 §5 — one per Product, trusts only its repo, pushes only to
  # team-<team>/<product>-*). The v2 per-team roles were removed at the cutover (the per-Product roles replace
  # them; tenant ECR repos are Composition-owned, so nothing is read from the `ecr` unit).
  roles = merge({
    # The developer portal's image-build role (Backstage; platform infra, ADR-051). Trusts ONLY the
    # asanexample/backstage repo on main; can push ONLY to platform/backstage.
    "github-actions-ecr-push-backstage" = {
      repos    = ["backstage"]
      branches = ["main"]
      events   = [] # main only — no PR preview builds for the portal
      tags     = { Service = "backstage" }

      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid      = "ECRAuth"
            Effect   = "Allow"
            Action   = ["ecr:GetAuthorizationToken"]
            Resource = "*"
          },
          {
            Sid    = "ECRPush"
            Effect = "Allow"
            Action = [
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "ecr:PutImage",
              "ecr:InitiateLayerUpload",
              "ecr:UploadLayerPart",
              "ecr:CompleteLayerUpload",
            ]
            Resource = [dependency.ecr.outputs.repository_arns["platform/backstage"]]
          },
        ]
      })
    }
    # The self-hosted ARC runner image-build role (ADR-065 / #323). Trusts ONLY the asanexample/platform repo
    # on main; can push ONLY to platform/gha-runner. Deliberately a SEPARATE role from the repo's other trusts
    # (Terratest in the test account; the future deployer role) — least privilege, no shared blast radius.
    "github-actions-ecr-push-gha-runner" = {
      repos    = ["platform"]
      branches = ["main"]
      events   = [] # main only — the image rebuilds on merge (no PR preview builds)
      tags     = { Service = "gha-runner" }

      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid      = "ECRAuth"
            Effect   = "Allow"
            Action   = ["ecr:GetAuthorizationToken"]
            Resource = "*"
          },
          {
            Sid    = "ECRPush"
            Effect = "Allow"
            Action = [
              "ecr:BatchCheckLayerAvailability",
              "ecr:GetDownloadUrlForLayer",
              "ecr:BatchGetImage",
              "ecr:PutImage",
              "ecr:InitiateLayerUpload",
              "ecr:UploadLayerPart",
              "ecr:CompleteLayerUpload",
            ]
            Resource = [dependency.ecr.outputs.repository_arns["platform/gha-runner"]]
          },
        ]
      })
    }
  }, local.product_roles) # per-Product roles (ADR-069 §5) — derived from the Product registry

  tags = include.base.locals.tags
}
