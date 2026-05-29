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

inputs = {
  create = true

  roles = {
    PlatformAdmin = {
      description          = "Platform team cluster access"
      max_session_duration = 14400

      # Trusted by SSO administrators in management and platform accounts
      trust_principals = {
        aws = [
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",     # Management account
          "arn:aws:iam::${include.base.locals.account_ids["platform"]}:root", # Platform account (self)
        ]
      }

      # Only SSO AdministratorAccess role holders can assume this role
      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
            "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
          ]
        },
      ]

      # Broad read across the platform comes from the AWS-managed ReadOnlyAccess
      # policy. PlatformAdmin authors nothing directly — AWS changes flow through
      # Terragrunt/PlatformDeployer, K8s through ArgoCD; emergencies use break-glass.
      managed_policies = ["arn:aws:iam::aws:policy/ReadOnlyAccess"]

      inline_policies = {
        # Deny sensitive data/secret exfil (Deny overrides ReadOnlyAccess), and grant
        # only the non-read SSM session actions needed to reach the cluster via the
        # bastion. See ADR-040.
        platform-admin-guardrails = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Sid    = "DenySensitiveDataReads"
              Effect = "Deny"
              Action = [
                "secretsmanager:GetSecretValue",
                "kms:Decrypt",
                "s3:GetObject*",
                "dynamodb:GetItem",
                "dynamodb:BatchGetItem",
                "dynamodb:Query",
                "dynamodb:Scan",
                "ssm:GetParameter",
                "ssm:GetParameters",
                "ssm:GetParametersByPath",
              ]
              Resource = "*"
            },
            {
              # SSM Session Manager to the bastion only (reach the private cluster).
              Sid      = "SSMStartSessionBastion"
              Effect   = "Allow"
              Action   = ["ssm:StartSession"]
              Resource = "arn:aws:ec2:*:*:instance/*"
              Condition = {
                StringEquals = {
                  "ssm:resourceTag/Name" = "${include.base.locals.env}-${include.base.locals.region_abbv}-ssm-bastion"
                }
              }
            },
            {
              Sid      = "SSMStartSessionPortForwardDoc"
              Effect   = "Allow"
              Action   = ["ssm:StartSession"]
              Resource = "arn:aws:ssm:*::document/AWS-StartPortForwardingSessionToRemoteHost"
            },
            {
              Sid      = "SSMManageOwnSessions"
              Effect   = "Allow"
              Action   = ["ssm:TerminateSession", "ssm:ResumeSession"]
              Resource = "*"
            },
          ]
        })
      }
    }

    PlatformDeployer = {
      description          = "Terragrunt infrastructure provisioning"
      max_session_duration = 7200 # 2 hours — long enough for full-stack applies

      trust_principals = {
        aws = [
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",     # Management account
          "arn:aws:iam::${include.base.locals.account_ids["platform"]}:root", # Platform account (self)
        ]
      }

      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }

    DeveloperAccess = {
      description          = "Namespace-scoped developer cluster access"
      max_session_duration = 14400

      trust_principals = {
        aws = [
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",     # Management account
          "arn:aws:iam::${include.base.locals.account_ids["platform"]}:root", # Platform account (self)
        ]
      }

      # SSO PowerUser or Admin role holders can assume DeveloperAccess
      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PowerUserAccess_*",
            "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
            "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PowerUserAccess_*",
            "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
          ]
        },
      ]

      managed_policies = []

      inline_policies = {
        eks-access = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Sid    = "EKSAccess"
              Effect = "Allow"
              Action = [
                "eks:DescribeCluster",
                "eks:ListClusters",
              ]
              Resource = "*"
            },
            {
              Sid      = "Identity"
              Effect   = "Allow"
              Action   = ["sts:GetCallerIdentity"]
              Resource = "*"
            },
          ]
        })
      }
    }
  }

  tags = include.base.locals.tags
}
