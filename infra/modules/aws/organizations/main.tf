locals {
  create = var.create
  root_id = local.create ? (
    var.create_organization
    ? aws_organizations_organization.this[0].roots[0].id
    : data.aws_organizations_organization.current[0].roots[0].id
  ) : null

  exempt_role_arns = [for role in var.exempt_roles :
    "arn:aws:iam::*:role/${role}"
  ]

  ou_parent_map = { for k, v in var.organizational_units :
    k => v.parent == null ? local.root_id : aws_organizations_organizational_unit.this[v.parent].id
  }

  effective_scps = var.service_control_policies != null ? var.service_control_policies : local.default_scps

  default_scps = merge(
    { for k, v in {
      "baseline-guardrails"       = data.aws_iam_policy_document.baseline_guardrails[0].json
      "protect-security-services" = data.aws_iam_policy_document.protect_security_services[0].json
      "enforce-encryption"        = data.aws_iam_policy_document.enforce_encryption[0].json
      "deny-regions"              = data.aws_iam_policy_document.deny_regions[0].json
      "protect-data-and-network"  = data.aws_iam_policy_document.protect_data_and_network[0].json
      "require-tagging"           = data.aws_iam_policy_document.require_tagging[0].json
      "restrict-iam-users"        = data.aws_iam_policy_document.restrict_iam_users[0].json
      } : k => v if local.create && var.service_control_policies == null
    },
    var.enable_hipaa_scp && local.create && var.service_control_policies == null ? {
      "hipaa-eligible-services" = data.aws_iam_policy_document.hipaa_eligible_services[0].json
    } : {}
  )

  scp_attachment_pairs = flatten([
    for target, policies in var.scp_attachments : [
      for policy in policies : {
        key       = "${target}/${policy}"
        target_id = target == "root" ? local.root_id : aws_organizations_organizational_unit.this[target].id
        policy_id = aws_organizations_policy.this[policy].id
      }
    ]
  ])
}

data "aws_organizations_organization" "current" {
  count = local.create && !var.create_organization ? 1 : 0
}

resource "aws_organizations_organization" "this" {
  count                         = local.create && var.create_organization ? 1 : 0
  aws_service_access_principals = var.organization_aws_service_access_principals
  enabled_policy_types          = var.organization_enabled_policy_types
  feature_set                   = "ALL"
  lifecycle { prevent_destroy = true }
}

resource "aws_organizations_organizational_unit" "this" {
  for_each  = local.create ? var.organizational_units : {}
  name      = each.key
  parent_id = local.ou_parent_map[each.key]
  tags      = var.tags
  lifecycle { prevent_destroy = true }
}

resource "aws_organizations_account" "this" {
  for_each          = local.create ? var.accounts : {}
  name              = each.key
  email             = each.value.email
  parent_id         = each.value.ou != null ? aws_organizations_organizational_unit.this[each.value.ou].id : local.root_id
  close_on_deletion = false
  tags              = var.tags
  lifecycle { ignore_changes = [role_name] }
}

resource "aws_organizations_policy" "this" {
  for_each    = local.effective_scps
  name        = each.key
  description = "Managed SCP: ${each.key}"
  type        = "SERVICE_CONTROL_POLICY"
  content     = each.value
  tags        = var.tags
}

resource "aws_organizations_policy_attachment" "this" {
  for_each  = { for pair in local.scp_attachment_pairs : pair.key => pair }
  policy_id = each.value.policy_id
  target_id = each.value.target_id
}
