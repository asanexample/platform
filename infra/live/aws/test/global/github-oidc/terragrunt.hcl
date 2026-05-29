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
  create     = true
  github_org = "gangster"

  roles = {
    "github-actions-terratest" = {
      repos = ["platform"]
      # Allow CI from main and feature branches (Terratest runs on PRs)
      branches = ["main", "refs/heads/feat/*"]
      # AdministratorAccess required because Terratest creates and destroys real AWS resources
      role_policy_arns     = ["arn:aws:iam::aws:policy/AdministratorAccess"]
      max_session_duration = 3600 # 1 hour — sufficient for Terratest runs
    }
  }

  tags = include.base.locals.tags
}
