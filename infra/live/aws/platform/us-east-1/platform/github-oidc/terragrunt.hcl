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
      "team-alpha/demo" = "arn:aws:ecr:us-east-1:000000000000:repository/team-alpha/demo"
      "team-bravo/demo" = "arn:aws:ecr:us-east-1:000000000000:repository/team-bravo/demo"
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
  github_org = "gangster"

  # One push role per team: trusts only that team's repo (OIDC sub) and can push
  # only to that team's ECR repos. Generated for teams that have ≥1 ECR repo.
  roles = { for team, cfg in local.teams :
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
            # Only this team's repositories (team-<team>/*).
            Resource = [
              for k, arn in dependency.ecr.outputs.repository_arns : arn
              if startswith(k, "team-${team}/")
            ]
          },
        ]
      })
    }
    if length([for k, _ in dependency.ecr.outputs.repository_arns : k if startswith(k, "team-${team}/")]) > 0
  }

  tags = include.base.locals.tags
}
