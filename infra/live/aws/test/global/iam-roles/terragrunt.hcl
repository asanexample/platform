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

# Onboards the Test sandbox account to the standard Terraform-managed posture: PlatformDeployer is the
# IaC principal here, as the org SCPs expect (DenyTeamTagTampering exempts PlatformDeployer, not human
# SSO admins). All test-env Terragrunt applies run as AWS_PROFILE=management -> assume PlatformDeployer.
# Bootstrap (first apply, before this role exists) uses the SCP-exempt OrganizationAccountAccessRole via
# a temporary provider override — see docs/runbooks/test-sandbox-account.md.
#
# Only PlatformDeployer is created here (not PlatformAdmin/DeveloperAccess): the Test account runs no
# cluster, so there is no kubectl/operator access to grant.
inputs = {
  create = true

  roles = {
    PlatformDeployer = {
      description          = "Terragrunt infrastructure provisioning (Test sandbox)"
      max_session_duration = 7200

      trust_principals = {
        aws = [
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root", # Management account (Terragrunt runs from here)
          "arn:aws:iam::${include.base.locals.account_ids["test"]}:root", # Test account (self)
        ]
      }

      # High-value (AdministratorAccess) — restrict assumption to SSO AdministratorAccess holders, same
      # posture as platform/preprod (ADR-040 / issue #57).
      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
            "arn:aws:iam::${include.base.locals.account_ids["test"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
          ]
        },
      ]

      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }
  }

  tags = include.base.locals.tags
}
