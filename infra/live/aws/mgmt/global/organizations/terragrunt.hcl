include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.organizations
}

inputs = {
  create              = true
  create_organization = true
  tags                = include.base.locals.tags
  allowed_regions     = ["us-east-1", "us-west-2"]
  required_tags       = ["Environment", "ManagedBy", "Owner"]

  organizational_units = {
    "Platform"            = { parent = null }
    "Workloads"           = { parent = null }
    "Workloads/Preprod"   = { parent = "Workloads" }
    "Workloads/Prod"      = { parent = "Workloads" }
    "Workloads/Regulated" = { parent = "Workloads" }
  }

  accounts = {
    "Platform" = { email = "josh+platform@deeden.org", ou = "Platform" }
    "Preprod"  = { email = "josh+preprod@deeden.org", ou = "Workloads/Preprod" }
    "Prod"     = { email = "josh+prod@deeden.org", ou = "Workloads/Prod" }
  }
}
