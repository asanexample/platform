include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.ecr
}

inputs = {
  create = true

  # ECR naming convention: team-<team>/<app> (matches teams.hcl app keys)
  repositories = {
    "team-alpha/demo" = {}
    "team-bravo/demo" = {}
  }

  # Accounts granted cross-account image pull access
  pull_account_ids = [
    "620830101009", # Preprod
    "554518885123", # Prod
  ]

  tags = include.base.locals.tags
}
