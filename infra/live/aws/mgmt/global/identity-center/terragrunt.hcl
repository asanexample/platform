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

    # Per-team developer permission sets (preprod). Each grants account-wide
    # read-only visibility plus the ability to assume only its own team's
    # DeveloperAccess role (the launchpad into namespace-scoped kubectl).
    # Hand-maintained: adding a team means adding an entry here, in the matching
    # group/assignment below, and in preprod teams.hcl.
    "Dev-alpha" = {
      description      = "Developer access for team alpha (preprod)"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid      = "AssumeTeamDeveloperRole"
          Effect   = "Allow"
          Action   = "sts:AssumeRole"
          Resource = "arn:aws:iam::${dependency.organizations.outputs.account_ids["Preprod"]}:role/DeveloperAccess-alpha"
        }]
      })
    }
    "Dev-bravo" = {
      description      = "Developer access for team bravo (preprod)"
      session_duration = "PT4H"
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]
      inline_policy = jsonencode({
        Version = "2012-10-17"
        Statement = [{
          Sid      = "AssumeTeamDeveloperRole"
          Effect   = "Allow"
          Action   = "sts:AssumeRole"
          Resource = "arn:aws:iam::${dependency.organizations.outputs.account_ids["Preprod"]}:role/DeveloperAccess-bravo"
        }]
      })
    }
  }

  groups = {
    "Admins"           = { description = "Full administrator access to all accounts" }
    "ReadOnly"         = { description = "Read-only access for auditing" }
    "Developers-alpha" = { description = "Developers for team alpha" }
    "Developers-bravo" = { description = "Developers for team bravo" }
  }

  users = {
    "josh" = {
      given_name  = "Josh"
      family_name = "Deeden"
      email       = include.base.locals.admin_email
      groups      = ["Admins"]
    }

    # Sample developers for validating per-team isolation (ADR-039). One per team
    # so we can confirm a dev can edit only their own namespace. Emails are
    # plus-addressed on the org domain (from admin_email) — replace with the real
    # addresses before these users need to sign in via SSO.
    "alpha-dev" = {
      given_name  = "Alpha"
      family_name = "Developer"
      email       = "alpha-dev+test@${split("@", include.base.locals.admin_email)[1]}"
      groups      = ["Developers-alpha"]
    }
    "bravo-dev" = {
      given_name  = "Bravo"
      family_name = "Developer"
      email       = "bravo-dev+test@${split("@", include.base.locals.admin_email)[1]}"
      groups      = ["Developers-bravo"]
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
    # Each team's developers get their own per-team permission set on Preprod
    # (account-wide read + assume their DeveloperAccess-<team> role). Replaces the
    # former broad Developers -> PowerUserAccess assignment, which would have let
    # any developer read/write every team's AWS resources and bypass namespace RBAC.
    { account_id = dependency.organizations.outputs.account_ids["Preprod"], permission_set = "Dev-alpha", group = "Developers-alpha" },
    { account_id = dependency.organizations.outputs.account_ids["Preprod"], permission_set = "Dev-bravo", group = "Developers-bravo" },
  ]
}
