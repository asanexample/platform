# Common configuration for Azure Diagnostic Settings across environments

terraform {
  source = "${get_repo_root()}/infra/modules/azure//diagnostic_settings"
}

locals {
  common_vars = read_terragrunt_config(find_in_parent_folders("common.hcl"))
  common_tags = local.common_vars.locals.tags
}

inputs = {
  tags = local.common_tags
}
