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
  exempt_roles        = ["OrganizationAccountAccessRole", "github-actions-terratest", "PlatformDeployer"]

  organizational_units = {
    "Platform"            = { parent = null }
    "Workloads"           = { parent = null }
    "Workloads/Preprod"   = { parent = "Workloads" }
    "Workloads/Prod"      = { parent = "Workloads" }
    "Workloads/Regulated" = { parent = "Workloads" }
  }

  accounts = {
    "Platform" = { email = include.base.locals.account_emails["platform"], ou = "Platform" }
    "Test"     = { email = include.base.locals.account_emails["test"], ou = "Platform" }
    "Preprod"  = { email = include.base.locals.account_emails["preprod"], ou = "Workloads/Preprod" }
    "Prod"     = { email = include.base.locals.account_emails["prod"], ou = "Workloads/Prod" }
  }
}
