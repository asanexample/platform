locals {
  create = var.create

  policy_attachments = local.create ? flatten([
    for role_name, role in var.roles : [
      for policy_arn in role.managed_policies : {
        key        = "${role_name}-${basename(policy_arn)}"
        role_name  = role_name
        policy_arn = policy_arn
      }
    ]
  ]) : []

  inline_policies = local.create ? flatten([
    for role_name, role in var.roles : [
      for policy_name, policy_json in role.inline_policies : {
        key         = "${role_name}-${policy_name}"
        role_name   = role_name
        policy_name = policy_name
        policy_json = policy_json
      }
    ]
  ]) : []
}

data "aws_iam_policy_document" "trust" {
  for_each = local.create ? var.roles : {}

  statement {
    effect  = "Allow"
    actions = each.value.trust_actions

    # Iterate the trust_principals map so roles can trust AWS principals (the common case) and/or a
    # service principal (e.g. pods.eks.amazonaws.com for EKS Pod Identity). For the {aws=[...]} shape
    # this renders one type="AWS" block — byte-identical to the previous static block.
    dynamic "principals" {
      for_each = each.value.trust_principals
      content {
        type        = lookup({ aws = "AWS", service = "Service", federated = "Federated" }, principals.key, "AWS")
        identifiers = principals.value
      }
    }

    dynamic "condition" {
      for_each = each.value.trust_conditions
      content {
        test     = condition.value.test
        variable = condition.value.variable
        values   = condition.value.values
      }
    }
  }
}

resource "aws_iam_role" "this" {
  for_each = local.create ? var.roles : {}

  name                 = each.key
  description          = each.value.description
  path                 = each.value.path
  max_session_duration = each.value.max_session_duration
  assume_role_policy   = data.aws_iam_policy_document.trust[each.key].json

  tags = merge(var.tags, each.value.tags)
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each = { for pa in local.policy_attachments : pa.key => pa }

  role       = aws_iam_role.this[each.value.role_name].name
  policy_arn = each.value.policy_arn
}

resource "aws_iam_role_policy" "this" {
  for_each = { for ip in local.inline_policies : ip.key => ip }

  name   = each.value.policy_name
  role   = aws_iam_role.this[each.value.role_name].name
  policy = each.value.policy_json
}
