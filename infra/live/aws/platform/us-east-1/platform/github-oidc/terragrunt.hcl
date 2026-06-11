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
  # Claim-as-single-source (ADR-061): the per-team app repos come from the XTenant claims (spec.apps.<app>.repo,
  # owner/repo), not a hand-maintained list. Each team gets its own ECR push role that can push ONLY to its own
  # team-<team>/* repos and trusts ONLY that team's repo(s). One app per team today; take every app's repo name.
  claims_dir = "${get_repo_root()}/gitops/tenant-claims/preprod"
  claims = { for f in fileset(local.claims_dir, "*.yaml") :
    yamldecode(file("${local.claims_dir}/${f}")).spec.team => yamldecode(file("${local.claims_dir}/${f}"))
  }
  team_repo_names = { for team, claim in local.claims :
    team => [for _app, cfg in claim.spec.apps : split("/", cfg.repo)[1]]
  }

  # ---------------------------------------------------------------------------
  # v3 (ADR-069 §5) — one OIDC ECR-push role per PRODUCT, derived from the Product registry
  # (gitops/products/<team>/<product>.yaml): trusts only the Product's repo, pushes only to its product-scoped
  # ECR (team-<team>/<product>-*). ADDITIVE + GATED: `v3_delivery_enabled` stays false until the cutover, so the
  # fileset is not even evaluated and no v3 roles are created on apply (it coexists with the v2 per-team roles).
  # The v2->v3 cutover flips this true and removes the per-team derivation above.
  # ---------------------------------------------------------------------------
  v3_delivery_enabled = false
  products_dir        = "${get_repo_root()}/gitops/products"
  products = local.v3_delivery_enabled ? {
    for f in fileset(local.products_dir, "**/*.yaml") :
    yamldecode(file("${local.products_dir}/${f}")).metadata.name => {
      team    = yamldecode(file("${local.products_dir}/${f}")).spec.team
      product = trimsuffix(basename(f), ".yaml") # short name (the filename) = the gitops/.../<product>.yaml stem
      repo    = yamldecode(file("${local.products_dir}/${f}")).spec.repo
    }
  } : {}
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

  # One push role per team: trusts only that team's repo (OIDC sub) and can push only to that team's
  # team-<team>/* ECR repos. The repo ARN is CONSTRUCTED (wildcard), not read from the `ecr` unit — the
  # tenant ECR repos are owned by the Crossplane Tenant Composition now (BACK stack P3), so the `ecr` unit
  # no longer lists them. (Keying off `ecr` here would silently drop every team's role — #174 regression.)
  roles = merge({ for team, repo_names in local.team_repo_names :
    "github-actions-ecr-push-${team}" => {
      repos    = repo_names
      branches = ["main"]         # push on merge to main
      events   = ["pull_request"] # and PR preview builds
      tags     = { Team = team }  # per-team attribution / ABAC (#61)

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
            # Only this team's repositories (team-<team>/*), Composition-created. Wildcard by construction.
            Resource = ["arn:aws:ecr:${include.base.locals.region}:${include.base.locals.account_id}:repository/team-${team}/*"]
          },
        ]
      })
    }
    }, {
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
  }, local.product_roles) # v3 per-Product roles (ADR-069 §5) — empty until the cutover flips v3_delivery_enabled

  tags = include.base.locals.tags
}
