include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Override remote_state to local backend — this module creates the S3 bucket
# that all other modules store their state in. Chicken-and-egg: it can't use
# a bucket that doesn't exist yet.
remote_state {
  backend = "local"
  generate = {
    path      = "backend.tf"
    if_exists = "overwrite_terragrunt"
  }
  config = {
    path = "${get_terragrunt_dir()}/terraform.tfstate"
  }
}

terraform {
  source = include.base.locals.module_source.state_bootstrap
}

inputs = {
  create              = true
  bucket_name         = "tfstate-mgmt-${include.base.locals.account_ids["mgmt"]}"
  dynamodb_table_name = "terraform-locks"
  tags                = include.base.locals.tags
}
