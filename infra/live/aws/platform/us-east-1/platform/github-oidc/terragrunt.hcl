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
      "team-alpha/demo"    = "arn:aws:ecr:us-east-1:000000000000:repository/team-alpha/demo"
      "team-bravo/demo"    = "arn:aws:ecr:us-east-1:000000000000:repository/team-bravo/demo"
      "platform/backstage" = "arn:aws:ecr:us-east-1:000000000000:repository/platform/backstage"
    }
  }
  mock_outputs_allowed_terraform_commands = ["init", "validate", "plan", "destroy"]
}

locals {
  # Team -> GitHub app repo. Hand-maintained alongside the ecr `repositories` list
  # in this account (see tenant-onboarding runbook). Each team gets its own ECR
  # push role that can push ONLY to its own team-<team>/* repos.
  teams = {
    alpha = { github_repo = "app-alpha" }
    bravo = { github_repo = "app-bravo" }
  }
}

inputs = {
  create     = true
  github_org = "asanexample"

  # One push role per team: trusts only that team's repo (OIDC sub) and can push only to that team's
  # team-<team>/* ECR repos. The repo ARN is CONSTRUCTED (wildcard), not read from the `ecr` unit — the
  # tenant ECR repos are owned by the Crossplane Tenant Composition now (BACK stack P3), so the `ecr` unit
  # no longer lists them. (Keying off `ecr` here would silently drop every team's role — #174 regression.)
  roles = merge({ for team, cfg in local.teams :
    "github-actions-ecr-push-${team}" => {
      repos    = [cfg.github_repo]
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
  })

  tags = include.base.locals.tags
}
