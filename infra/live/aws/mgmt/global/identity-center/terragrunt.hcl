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

# Ordering only (so a from-scratch bootstrap applies organizations first). Account IDs come from
# include.base.locals.account_ids (SOPS, ADR-066) — NOT a dependency output, because Terragrunt evaluates
# `locals` before dependency outputs are available, and the generation below runs in `locals`.
dependencies {
  paths = ["../organizations"]
}

# ---------------------------------------------------------------------------------------------------
# AWS Identity Center, GENERATED from the registries (identity strategy §2.6, #888). The Identity Store
# users/groups + permission-set account-assignments are DERIVED from gitops/people (the roster) joined with
# gitops/roles (the catalog, #887) — the same fileset/yamldecode pattern keycloak-config uses — instead of a
# hand-maintained list. "Add a person" is now a roster PR; this unit projects it into AWS console access.
#
# decide/apply split (§3.3): the generation here is the DECIDE; the identity_center module's `check` blocks are
# the machine-checkable invariants (assignments/memberships reference known groups+permission-sets; no wildcard
# Allow in an inline policy) asserted before APPLY — so a translation bug can't silently over-grant.
#
# STANDING vs on-demand (§2.3): only STANDING grants get a standing assignment here. A grant that is
# `activation: on-demand` (or whose role's mode is on-demand, e.g. platform-operator / break-glass) is
# ELIGIBILITY, not standing — P3's activation controller grants it at checkout. So borrowed power never sits as a
# standing console assignment.
#
# ⚠️ CUTOVER (no-lockout, §3.6 — live IAM in the management account): this REPLACES the prior hand-maintained
# users/groups/assignments. Do NOT big-bang. Dual-run → verify-parity → flip with the independent break-glass
# (OrganizationAccountAccessRole / a bootstrap admin) live throughout:
#   1. `AWS_PROFILE=management terragrunt plan` from the MAIN repo root — read the diff. Expect the unused legacy
#      ReadOnly/PowerUser permission sets + the empty ReadOnly group to be removed; confirm every CURRENT human
#      keeps an equivalent permission set on the same accounts (josh→AdministratorAccess everywhere; each
#      team dev→Dev-<team> on preprod). There WILL be destroys (legacy unused objects) — verify they are only the
#      unused ones, never a still-needed assignment.
#   2. Apply; immediately verify each person can still reach the AWS access portal with the right permission set.
#   3. Keep break-glass available until verified. Never enable anything that depends on the system being migrated.
# ---------------------------------------------------------------------------------------------------
locals {
  people_dir = "${get_repo_root()}/gitops/people"
  roles_dir  = "${get_repo_root()}/gitops/roles"

  # Roster + catalog (access facts only — no PII; the people files carry a Keycloak anchor, not an email).
  people = { for f in fileset(local.people_dir, "*.yaml") :
    yamldecode(file("${local.people_dir}/${f}")).metadata.name => yamldecode(file("${local.people_dir}/${f}")).spec
  }
  roles = { for f in fileset(local.roles_dir, "*.yaml") :
    yamldecode(file("${local.roles_dir}/${f}")).metadata.name => yamldecode(file("${local.roles_dir}/${f}")).spec
  }

  # Account targets. Platform roles scope by permission set (admin/RO everywhere; PowerUser off the mgmt account);
  # team developer access is preprod-only (the per-team DeveloperAccess-<team> launchpad, ADR-039).
  acct_mgmt     = include.base.locals.account_ids["mgmt"]
  acct_platform = include.base.locals.account_ids["platform"]
  acct_preprod  = include.base.locals.account_ids["preprod"]
  acct_prod     = include.base.locals.account_ids["prod"]
  all_accounts  = [local.acct_mgmt, local.acct_platform, local.acct_preprod, local.acct_prod]
  ps_accounts = {
    AdministratorAccess = local.all_accounts
    PowerUserAccess     = [local.acct_platform, local.acct_preprod, local.acct_prod]
    ReadOnlyAccess      = local.all_accounts
  }

  domain = split("@", include.base.locals.admin_email)[1]

  # STANDING grants with an AWS console projection (role has an identityCenter block). on-demand → P3, not here.
  standing_grants = flatten([
    for pname, p in local.people : [
      for g in p.grants : merge(g, { person = pname })
      if try(g.activation, "") != "on-demand"
      && try(local.roles[g.role].mode, "standing") == "standing"
      && try(local.roles[g.role].identityCenter, null) != null
    ]
  ])

  # Teams with a standing team-grant → a Dev-<team> permission set whose inline policy is the per-team ABAC
  # launchpad (assume DeveloperAccess-<team> in preprod + deny acting on another team's tagged resources, #62).
  team_set = distinct([for g in local.standing_grants : g.team if try(g.team, "") != ""])
  dev_inline = { for t in local.team_set : t => jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "AssumeTeamDeveloperRole"
        Effect   = "Allow"
        Action   = "sts:AssumeRole"
        Resource = "arn:aws:iam::${local.acct_preprod}:role/DeveloperAccess-${t}"
      },
      {
        Sid      = "DenyOtherTeamsResources"
        Effect   = "Deny"
        Action   = "*"
        Resource = "*"
        Condition = {
          StringNotEquals = { "aws:ResourceTag/Team" = [t, "platform"] }
          Null            = { "aws:ResourceTag/Team" = "false" }
        }
      },
    ]
  }) }

  # Per-grant projection: a team grant → the Dev-<team> set on preprod via a Developers-<team> group; a platform
  # grant → the role's named permission set on its scoped accounts via a group named after the role.
  grant_proj = [
    for g in local.standing_grants : (
      try(g.team, "") != "" ? {
        person           = g.person
        group            = "Developers-${g.team}"
        permission_set   = "Dev-${g.team}"
        accounts         = [local.acct_preprod]
        session_duration = try(local.roles[g.role].identityCenter.sessionDuration, "PT4H")
        managed_policies = try(local.roles[g.role].identityCenter.managedPolicies, [])
        inline_policy    = local.dev_inline[g.team]
        is_team          = true
        } : {
        person           = g.person
        group            = g.role
        permission_set   = local.roles[g.role].identityCenter.permissionSet
        accounts         = lookup(local.ps_accounts, local.roles[g.role].identityCenter.permissionSet, local.all_accounts)
        session_duration = try(local.roles[g.role].identityCenter.sessionDuration, "PT4H")
        managed_policies = try(local.roles[g.role].identityCenter.managedPolicies, [])
        inline_policy    = null
        is_team          = false
      }
    )
  ]

  # --- aggregate into the module inputs (map comprehensions dedup by key) ---------------------------
  gen_permission_sets = {
    for gp in local.grant_proj : gp.permission_set => {
      description      = gp.is_team ? "Per-team developer access (generated from the role catalog, #888)." : "Platform role permission set (generated, #888)."
      session_duration = gp.session_duration
      managed_policies = gp.managed_policies
      inline_policy    = gp.inline_policy
    }
  }

  gen_groups = {
    for gp in local.grant_proj : gp.group => {
      description = gp.is_team ? "Team developers — generated from the roster (#888)." : "Workforce role '${gp.group}' — generated from the roster (#888)."
    }
  }

  gen_users = {
    for pname, p in local.people : pname => {
      # Synthetic display fields derived from the roster name — the real identity (email/name) lives in Keycloak +
      # the ADR-084 directory, never in git. josh is the management contact; everyone else is plus-addressed.
      given_name  = title(split("-", pname)[0])
      family_name = length(split("-", pname)) > 1 ? title(split("-", pname)[1]) : "User"
      email       = pname == "josh" ? include.base.locals.admin_email : "${pname}+test@${local.domain}"
      groups      = distinct([for gp in local.grant_proj : gp.group if gp.person == pname])
    }
  }

  gen_assignments = distinct(flatten([
    for gp in local.grant_proj : [
      for a in gp.accounts : { account_id = a, permission_set = gp.permission_set, group = gp.group }
    ]
  ]))
}

inputs = {
  create = true
  tags   = include.base.locals.tags

  permission_sets     = local.gen_permission_sets
  groups              = local.gen_groups
  users               = local.gen_users
  account_assignments = local.gen_assignments
}
