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
      "team-alpha/demo"              = "arn:aws:ecr:us-east-1:000000000000:repository/team-alpha/demo"
      "team-bravo/demo"              = "arn:aws:ecr:us-east-1:000000000000:repository/team-bravo/demo"
      "platform/backstage"           = "arn:aws:ecr:us-east-1:000000000000:repository/platform/backstage"
      "platform/gha-runner"          = "arn:aws:ecr:us-east-1:000000000000:repository/platform/gha-runner"
      "platform/activation-operator" = "arn:aws:ecr:us-east-1:000000000000:repository/platform/activation-operator"
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
              # The shared build-sign workflow polls describe-repositories to confirm the Composition-created ECR
              # repo exists before building (ADR-071 "wait for delivery infra"); without it the first deploy of a
              # new Product loops until timeout even though it can push.
              "ecr:DescribeRepositories",
            ]
            # Only this product's repos (team-<team>/<product>-*), Composition-created. Wildcard by construction.
            Resource = ["arn:aws:ecr:${include.base.locals.region}:${include.base.locals.account_id}:repository/team-${p.team}/${p.product}-*"]
          },
          {
            # Read the promote App's key (ADR-071) so trusted-ci/promote.yml can mint an installation token and
            # open the release digest-bump PR — the per-Product role is the only identity that reads it (no GitHub
            # org secret, no key in the app repo). docs/runbooks/promote-github-app.md.
            Sid      = "PromoteAppSecret"
            Effect   = "Allow"
            Action   = ["secretsmanager:GetSecretValue"]
            Resource = ["arn:aws:secretsmanager:${include.base.locals.region}:${include.base.locals.account_id}:secret:platform/promote/github-app-*"]
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
    # The learning-portal TechDocs publish role (#938, ADR-097). Trusts ONLY the asanexample/platform repo on
    # main; can write ONLY to the refplat-platform-techdocs bucket. The techdocs.yml workflow builds the site (mkdocs +
    # techdocs-cli) and publishes it here (builder: external); Backstage serves it read-only.
    "github-actions-techdocs-publish" = {
      repos    = ["platform"]
      branches = ["main"]
      events   = [] # main only — the site republishes on merges that touch docs/learn
      tags     = { Service = "techdocs" }

      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [
          {
            Sid    = "TechDocsPublish"
            Effect = "Allow"
            Action = [
              "s3:PutObject",
              "s3:DeleteObject",
              "s3:GetObject",
              "s3:ListBucket",
            ]
            Resource = [
              "arn:aws:s3:::refplat-platform-techdocs",
              "arn:aws:s3:::refplat-platform-techdocs/*",
            ]
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
    # The activation operator image-build role (ADR-088). Trusts ONLY the asanexample/platform repo on main;
    # can push ONLY to platform/activation-operator. Separate role from gha-runner / the deployer — least
    # privilege, no shared blast radius (mirrors github-actions-ecr-push-gha-runner).
    "github-actions-ecr-push-activation-operator" = {
      repos    = ["platform"]
      branches = ["main"]
      events   = [] # main only — the image rebuilds on merge (no PR preview builds)
      tags     = { Service = "activation-operator" }

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
            Resource = [dependency.ecr.outputs.repository_arns["platform/activation-operator"]]
          },
        ]
      })
    }
    # The P13 tenant-proxy image-build role (#590). Trusts ONLY the asanexample/platform repo on main; can
    # push ONLY to platform/tenant-proxy. Separate least-privilege role (mirrors the activation-operator one).
    "github-actions-ecr-push-tenant-proxy" = {
      repos    = ["platform"]
      branches = ["main"]
      events   = [] # main only — the image rebuilds on merge (no PR preview builds)
      tags     = { Service = "tenant-proxy" }

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
            Resource = [dependency.ecr.outputs.repository_arns["platform/tenant-proxy"]]
          },
        ]
      })
    }
  }, local.product_roles) # per-Product roles (ADR-069 §5) — derived from the Product registry

  tags = include.base.locals.tags
}
