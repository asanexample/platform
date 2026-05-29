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

inputs = {
  create = true

  github_org    = "gangster"
  github_repos  = ["app-alpha", "app-bravo"] # Team app repos that push images to ECR
  github_events = ["pull_request"]           # Allow OIDC from PR workflows (preview image builds)

  role_name = "github-actions-ecr-push"

  # Scoped to ECR auth + push only — no other AWS access
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
        Resource = values(dependency.ecr.outputs.repository_arns)
      },
    ]
  })

  tags = include.base.locals.tags
}
