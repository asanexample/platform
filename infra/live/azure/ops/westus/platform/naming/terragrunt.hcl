# Terragrunt configuration for Azure naming standards in westus region

include "base" {
  path   = find_in_parent_folders("azure/_base.hcl")
  expose = true
}

# Include the root configuration (root.hcl)
include "root" {
  path = find_in_parent_folders("root.hcl")
}

# Include the common configuration for Naming
include "naming_common" {
  path = find_in_parent_folders("azure/_envcommon/naming.hcl")
}

# Use the appropriate Terraform module as the source
terraform {
  # Use double-slash notation to ensure all relative module references work correctly
  source = "${get_repo_root()}/infra/modules/azure//naming"
}

# Specify inputs specific to this module
inputs = {
  # Environment variables
  environment = include.base.locals.env
  workload    = include.base.locals.workload
  region_abbv = include.base.locals.region_abbv

  # Tags
  tags = include.base.locals.tags
}
