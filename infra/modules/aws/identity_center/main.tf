locals {
  create            = var.create
  instance_arn      = local.create ? one(data.aws_ssoadmin_instances.this[0].arns) : null
  identity_store_id = local.create ? one(data.aws_ssoadmin_instances.this[0].identity_store_ids) : null

  managed_policy_pairs = flatten([
    for ps_name, ps in var.permission_sets : [
      for policy_arn in coalesce(ps.managed_policies, []) : {
        key            = "${ps_name}/${element(split("/", policy_arn), length(split("/", policy_arn)) - 1)}"
        permission_set = ps_name
        policy_arn     = policy_arn
      }
    ]
  ])

  group_membership_pairs = flatten([
    for user_name, user in var.users : [
      for group in coalesce(user.groups, []) : {
        key   = "${user_name}/${group}"
        user  = user_name
        group = group
      }
    ]
  ])

  account_assignment_pairs = [
    for assignment in var.account_assignments : {
      key            = "${assignment.group}/${assignment.account_id}/${assignment.permission_set}"
      account_id     = assignment.account_id
      permission_set = assignment.permission_set
      group          = assignment.group
    }
  ]
}

data "aws_ssoadmin_instances" "this" {
  count = local.create ? 1 : 0
}

resource "aws_ssoadmin_permission_set" "this" {
  for_each         = local.create ? var.permission_sets : {}
  instance_arn     = local.instance_arn
  name             = each.key
  description      = each.value.description
  session_duration = each.value.session_duration
  tags             = var.tags
}

resource "aws_ssoadmin_managed_policy_attachment" "this" {
  for_each           = { for pair in local.managed_policy_pairs : pair.key => pair if local.create }
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  managed_policy_arn = each.value.policy_arn
}

resource "aws_ssoadmin_permission_set_inline_policy" "this" {
  for_each           = { for k, v in var.permission_sets : k => v if local.create && v.inline_policy != null }
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.key].arn
  inline_policy      = each.value.inline_policy
}

resource "aws_identitystore_group" "this" {
  for_each          = local.create ? var.groups : {}
  identity_store_id = local.identity_store_id
  display_name      = each.key
  description       = each.value.description
}

resource "aws_identitystore_user" "this" {
  for_each          = local.create ? var.users : {}
  identity_store_id = local.identity_store_id
  user_name         = each.key
  display_name      = coalesce(each.value.display_name, "${each.value.given_name} ${each.value.family_name}")

  name {
    given_name  = each.value.given_name
    family_name = each.value.family_name
  }

  emails {
    value   = each.value.email
    primary = true
  }
}

resource "aws_identitystore_group_membership" "this" {
  for_each          = { for pair in local.group_membership_pairs : pair.key => pair if local.create }
  identity_store_id = local.identity_store_id
  group_id          = aws_identitystore_group.this[each.value.group].group_id
  member_id         = aws_identitystore_user.this[each.value.user].user_id
}

resource "aws_ssoadmin_account_assignment" "this" {
  for_each           = { for pair in local.account_assignment_pairs : pair.key => pair if local.create }
  instance_arn       = local.instance_arn
  permission_set_arn = aws_ssoadmin_permission_set.this[each.value.permission_set].arn
  principal_id       = aws_identitystore_group.this[each.value.group].group_id
  principal_type     = "GROUP"
  target_id          = each.value.account_id
  target_type        = "AWS_ACCOUNT"
}
