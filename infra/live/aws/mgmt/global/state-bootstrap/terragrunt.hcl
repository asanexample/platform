include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

# Override remote_state to use local backend (bootstrapping)
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
  bucket_name         = "tfstate-mgmt-851725353202"
  dynamodb_table_name = "terraform-locks"
  tags                = include.base.locals.tags
}
