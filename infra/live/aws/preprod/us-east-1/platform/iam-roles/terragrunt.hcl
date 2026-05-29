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

locals {
  # Team definitions are the single source of truth (shared with the eks and
  # tenants units). One DeveloperAccess role is generated per namespace team.
  teams_config    = read_terragrunt_config("${get_terragrunt_dir()}/../teams.hcl")
  namespace_teams = local.teams_config.locals.namespace_teams
}

inputs = {
  create = true

  roles = merge({
    PlatformAdmin = {
      description          = "Platform team cluster access"
      max_session_duration = 14400

      # Trusted by SSO administrators in management and preprod accounts
      trust_principals = {
        aws = [
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",    # Management account
          "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:root", # Preprod account (self)
        ]
      }

      # Only SSO AdministratorAccess role holders can assume this role
      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values = [
            "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
            "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
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
              # Read-only EKS API access for cluster debugging — node groups,
              # add-ons, updates, access entries, etc. (not just the cluster).
              Action = [
                "eks:Describe*",
                "eks:List*",
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
            {
              # Scoped to preprod/* prefix — for debugging secrets-backed services
              Sid    = "SecretsReadForDebugging"
              Effect = "Allow"
              Action = [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
              ]
              Resource = "arn:aws:secretsmanager:*:${include.base.locals.account_ids["preprod"]}:secret:preprod/*"
            },
            {
              Sid      = "SecretsListForDebugging"
              Effect   = "Allow"
              Action   = ["secretsmanager:ListSecrets"]
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
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",    # Management account
          "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:root", # Preprod account (self)
        ]
      }

      managed_policies = ["arn:aws:iam::aws:policy/AdministratorAccess"]
    }

    # Assumed by ArgoCD IRSA service accounts in the platform cluster
    ArgoCD = {
      description = "Cross-account ArgoCD cluster management from platform hub"

      trust_principals = {
        aws = ["arn:aws:iam::${include.base.locals.account_ids["platform"]}:root"] # Platform account
      }

      # Only ArgoCD service account roles from the platform EKS cluster
      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values   = ["arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/platform-use1-eks-argocd-*"]
        },
      ]

      managed_policies = []
    }

    },

    # Per-team developer roles, generated from teams.hcl. Each role is scoped to
    # its team's namespace via an EKS access entry (in the eks unit) and is
    # assumable only by that team's SSO permission set (Dev-<team>).
    { for team, _ in local.namespace_teams :
      "DeveloperAccess-${team}" => {
        description          = "Namespace-scoped developer cluster access for team ${team}"
        max_session_duration = 14400
        managed_policies     = []

        trust_principals = {
          aws = [
            "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",    # Management account
            "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:root", # Preprod account (self)
          ]
        }

        # Only this team's SSO permission set (Dev-<team>) can assume the role.
        trust_conditions = [
          {
            test     = "ArnLike"
            variable = "aws:PrincipalArn"
            values = [
              "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Dev-${team}_*",
              "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_Dev-${team}_*",
            ]
          },
        ]

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
  })

  tags = include.base.locals.tags
}
