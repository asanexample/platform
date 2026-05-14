# Terragrunt configuration for Azure naming standards in eastus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders()
}

include "naming_common" {
  path = find_in_parent_folders("azure/_envcommon/naming.hcl")
}

terraform {
  source = "${get_repo_root()}/infra/modules/azure//naming"
}

inputs = {
  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  tags = include.base.locals.tags
}
