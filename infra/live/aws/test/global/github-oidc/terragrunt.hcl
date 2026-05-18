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
  create          = true
  github_org      = "gangster"
  github_repo     = "platform"
  github_branches = ["main", "refs/heads/feat/*"]
  role_name       = "github-actions-terratest"
  tags            = include.base.locals.tags

  role_policy_arns = [
    "arn:aws:iam::aws:policy/AdministratorAccess",
  ]

  max_session_duration = 3600
}
