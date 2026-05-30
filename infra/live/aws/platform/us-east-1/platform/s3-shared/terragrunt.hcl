include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.s3
}

locals {
  # Cross-account: tenant buckets live in the platform account but are read by the tenant Pod Identity
  # roles in preprod. Read the preprod teams.hcl to discover which teams declare AWS/S3 access.
  teams_config = read_terragrunt_config("${get_repo_root()}/infra/live/aws/preprod/us-east-1/platform/teams.hcl")
  aws_teams    = local.teams_config.locals.aws_teams

  org     = include.base.locals.org_name
  preprod = include.base.locals.account_ids["preprod"]

  # One bucket per (team, s3-suffix). Isolation by construction: the bucket name AND its sole reader are
  # both derived from the OWNING team key in the iteration — a bucket named for team X can only ever
  # grant Pod-team-X, regardless of any teams.hcl edit. (Shared/multi-reader buckets = future opt-in.)
  buckets = merge([
    for team, v in local.aws_teams : {
      for suffix, s in v.aws.s3 :
      "${local.org}-team-${team}-${suffix}" => {
        reader_role_arns = ["arn:aws:iam::${local.preprod}:role/Pod-team-${team}"]
        tags             = { Team = team }
      }
    }
  ]...)
}

inputs = {
  create  = true
  buckets = local.buckets
  tags    = include.base.locals.tags
}
