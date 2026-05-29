include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.identity_center
}

dependency "organizations" {
  config_path = "../organizations"
}

inputs = {
  create = true
  tags   = include.base.locals.tags

  permission_sets = {
    "AdministratorAccess" = {
      description      = "Full administrator access"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
    "ReadOnlyAccess" = {
      description      = "Read-only access for auditing"
      session_duration = "PT8H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
    }
    "PowerUserAccess" = {
      description      = "Full access minus IAM administration"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/PowerUserAccess"]
    }
  }

  groups = {
    "Admins"     = { description = "Full administrator access to all accounts" }
    "Developers" = { description = "Developer access to workload accounts" }
    "ReadOnly"   = { description = "Read-only access for auditing" }
  }

  users = {
    "josh" = {
      given_name  = "Josh"
      family_name = "Deeden"
      email       = include.base.locals.admin_email
      groups      = ["Admins"]
    }
  }

  account_assignments = [
    # Admins get AdministratorAccess on all accounts
    { account_id = include.base.locals.account_id, permission_set = "AdministratorAccess", group = "Admins" },
    { account_id = dependency.organizations.outputs.account_ids["Platform"], permission_set = "AdministratorAccess", group = "Admins" },
    { account_id = dependency.organizations.outputs.account_ids["Preprod"], permission_set = "AdministratorAccess", group = "Admins" },
    { account_id = dependency.organizations.outputs.account_ids["Prod"], permission_set = "AdministratorAccess", group = "Admins" },
    # ReadOnly gets ReadOnlyAccess on all accounts
    { account_id = include.base.locals.account_id, permission_set = "ReadOnlyAccess", group = "ReadOnly" },
    { account_id = dependency.organizations.outputs.account_ids["Platform"], permission_set = "ReadOnlyAccess", group = "ReadOnly" },
    { account_id = dependency.organizations.outputs.account_ids["Preprod"], permission_set = "ReadOnlyAccess", group = "ReadOnly" },
    { account_id = dependency.organizations.outputs.account_ids["Prod"], permission_set = "ReadOnlyAccess", group = "ReadOnly" },
    # Developers get PowerUserAccess on Preprod
    { account_id = dependency.organizations.outputs.account_ids["Preprod"], permission_set = "PowerUserAccess", group = "Developers" },
  ]
}
