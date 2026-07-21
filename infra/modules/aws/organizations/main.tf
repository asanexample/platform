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

  # Tag-SCP-only exemption (ADR-017 two-axis, #072): the blanket exempt_roles PLUS the tag-only
  # roles. Used ONLY by require-tagging + DenyTeamTagTampering — every OTHER SCP still binds these
  # roles. Keeps provisioners least-privileged: exempt from tag governance (they tag at create),
  # subject to all other guardrails. Empty tag_scp_exempt_roles → identical to exempt_role_arns.
  tag_scp_exempt_role_arns = concat(
    local.exempt_role_arns,
    [for role in var.tag_scp_exempt_roles : "arn:aws:iam::*:role/${role}"],
  )

  top_level_ous = { for k, v in var.organizational_units : k => v if v.parent == null }
  child_ous     = { for k, v in var.organizational_units : k => v if v.parent != null }

  all_ou_ids = merge(
    { for k, v in aws_organizations_organizational_unit.top_level : k => v.id },
    { for k, v in aws_organizations_organizational_unit.child : k => v.id },
  )

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
        target_id = target == "root" ? local.root_id : local.all_ou_ids[target]
        policy_id = aws_organizations_policy.this[policy].id
      }
    ]
  ])
}

# ---------------------------------------------------------------------------
# Organization
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Organizational Units
# ---------------------------------------------------------------------------

resource "aws_organizations_organizational_unit" "top_level" {
  for_each  = local.create ? local.top_level_ous : {}
  name      = each.key
  parent_id = local.root_id
  tags      = var.tags
  lifecycle { prevent_destroy = true }
}

resource "aws_organizations_organizational_unit" "child" {
  for_each = local.create ? local.child_ous : {}
  # Child OU keys use "Parent/Child" format; extract the last segment as the OU display name
  name      = element(split("/", each.key), length(split("/", each.key)) - 1)
  parent_id = aws_organizations_organizational_unit.top_level[each.value.parent].id
  tags      = var.tags
  lifecycle { prevent_destroy = true }
}

# ---------------------------------------------------------------------------
# Accounts
# ---------------------------------------------------------------------------

resource "aws_organizations_account" "this" {
  for_each          = local.create ? var.accounts : {}
  name              = each.key
  email             = each.value.email
  parent_id         = each.value.ou != null ? local.all_ou_ids[each.value.ou] : local.root_id
  close_on_deletion = false # Never close an AWS account when removed from Terraform state
  tags              = var.tags
  # AWS auto-populates role_name at account creation; ignoring prevents spurious diffs
  lifecycle { ignore_changes = [role_name] }
}

# ---------------------------------------------------------------------------
# Service Control Policies
# ---------------------------------------------------------------------------

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
