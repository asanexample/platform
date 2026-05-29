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

  repositories = {
    "team-alpha/demo" = {}
    "team-bravo/demo" = {}
  }

  pull_account_ids = ["620830101009", "554518885123"]

  tags = include.base.locals.tags
}
