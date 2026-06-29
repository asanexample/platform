include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.iam_roles
}

# Management-account IAM roles. Identity Center lives in the management account, so anything that must call
# the sso-admin APIs as a MACHINE (not a human SSO session) needs a role here, assumed cross-account.

inputs = {
  create = true

  roles = {
    # The activation operator's Identity Center plane (ADR-088). The operator runs on the platform/hub
    # cluster (platform account) and mints/revokes account assignments, which live in THIS (management)
    # account. Its hub Pod Identity role (platform-use1-eks-activation-operator) assumes this role to reach
    # sso-admin. This is the crown-jewel grant — it can assign any permission set (incl. AdministratorAccess)
    # in any account — so the trust is locked to EXACTLY that one Pod Identity role ARN and nothing else.
    "activation-operator-identity-center" = {
      description          = "Activation operator (ADR-088) cross-account Identity Center admin plane"
      max_session_duration = 3600

      trust_principals = {
        aws = ["arn:aws:iam::${include.base.locals.account_ids["platform"]}:root"]
      }
      # Pod Identity credential chains may carry session tags → allow TagSession alongside AssumeRole.
      trust_actions = ["sts:AssumeRole", "sts:TagSession"]
      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values   = ["arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/platform-use1-eks-activation-operator"]
        },
      ]

      inline_policies = {
        # Identity Center assignment lifecycle (read + mint + revoke + poll). The sso-admin APIs do not
        # support resource-level scoping, so Resource = "*"; the boundary is the trust above (only the
        # operator's Pod Identity role can assume this) plus the operator's own eligibility/cap fail-closed
        # logic. identitystore:ListUsers resolves a principal's user id by username before assigning.
        identity-center = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Sid    = "IdentityCenterAssignmentPlane"
              Effect = "Allow"
              Action = [
                "sso:ListInstances",
                "sso:ListPermissionSets",
                "sso:DescribePermissionSet",
                "sso:ListAccountsForProvisionedPermissionSet",
                "sso:ListAccountAssignments",
                "sso:CreateAccountAssignment",
                "sso:DeleteAccountAssignment",
                "sso:DescribeAccountAssignmentCreationStatus",
                "sso:DescribeAccountAssignmentDeletionStatus",
                "identitystore:ListUsers",
                "identitystore:GetUserId",
              ]
              Resource = "*"
            },
          ]
        })
      }
    }
  }

  tags = include.base.locals.tags
}
