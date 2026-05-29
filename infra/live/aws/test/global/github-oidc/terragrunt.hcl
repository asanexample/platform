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

inputs = {
  create      = true
  github_org  = "gangster"
  github_repo = "platform"
  # Allow CI from main and feature branches (Terratest runs on PRs)
  github_branches = ["main", "refs/heads/feat/*"]
  role_name       = "github-actions-terratest"
  tags            = include.base.locals.tags

  # AdministratorAccess required because Terratest creates and destroys real AWS resources
  role_policy_arns = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
  ]

  max_session_duration = 3600 # 1 hour — sufficient for Terratest runs
}
