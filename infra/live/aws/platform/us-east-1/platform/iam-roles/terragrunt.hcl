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

      trust_principals = {
        aws = [
          "arn:aws:iam::851725353202:root",
          "arn:aws:iam::829808296602:root",
        ]
      }

      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::851725353202:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
            "arn:aws:iam::829808296602:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
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
              Sid    = "SSMAccess"
              Effect = "Allow"
              Action = [
                "ssm:StartSession",
                "ssm:TerminateSession",
                "ssm:ResumeSession",
                "ssm:DescribeSessions",
                "ssm:GetConnectionStatus",
              ]
              Resource = "*"
            },
            {
              Sid      = "SSMDocumentAccess"
              Effect   = "Allow"
              Action   = ["ssm:StartSession"]
              Resource = "arn:aws:ssm:*::document/AWS-StartPortForwardingSessionToRemoteHost"
            },
            {
              Sid      = "EC2Describe"
              Effect   = "Allow"
              Action   = ["ec2:DescribeInstances"]
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

    PlatformDeployer = {
      description          = "Terragrunt infrastructure provisioning"
      max_session_duration = 7200

      trust_principals = {
        aws = [
          "arn:aws:iam::851725353202:root",
          "arn:aws:iam::829808296602:root",
        ]
      }

      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }

    DeveloperAccess = {
      description          = "Namespace-scoped developer cluster access"
      max_session_duration = 14400

      trust_principals = {
        aws = [
          "arn:aws:iam::851725353202:root",
          "arn:aws:iam::829808296602:root",
        ]
      }

      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::851725353202:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PowerUserAccess_*",
            "arn:aws:iam::851725353202:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
            "arn:aws:iam::829808296602:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_PowerUserAccess_*",
            "arn:aws:iam::829808296602:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
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
