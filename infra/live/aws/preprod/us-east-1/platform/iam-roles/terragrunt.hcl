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
  # Teams declaring AWS access — one EKS Pod Identity workload role each (ADR-041).
  aws_teams = local.teams_config.locals.aws_teams
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
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",    # Management account
          "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:root", # Preprod account (self)
        ]
      }

      # AdministratorAccess is high-value, so restrict assumption to SSO
      # AdministratorAccess role holders (Terragrunt runs from the management SSO
      # admin profile) — same posture as PlatformAdmin. See issue #57 / ADR-040.
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
        tags                 = { Team = team } # per-team attribution / ABAC (#61)

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
    },

    # Per-team EKS Pod Identity workload roles (ADR-041), generated from teams.hcl `aws` blocks. Trust is
    # the Pod Identity service principal, scoped to this account; the actual pod->role binding is the
    # association in the pod-identity unit. The inline policy grants the team's declared S3 access. The
    # cross-account bucket policy (platform s3-shared unit) is the other half of the cross-account grant.
    { for team, cfg in local.aws_teams :
      "Pod-team-${team}" => {
        description          = "EKS Pod Identity role for team ${team} workloads"
        max_session_duration = 3600
        managed_policies     = []
        tags                 = { Team = team }

        trust_principals = { service = ["pods.eks.amazonaws.com"] }
        trust_actions    = ["sts:AssumeRole", "sts:TagSession"]
        # Defense-in-depth: the role can only be assumed via a Pod Identity association in our account.
        trust_conditions = [
          {
            test     = "StringEquals"
            variable = "aws:SourceAccount"
            values   = [include.base.locals.account_ids["preprod"]]
          },
        ]

        # Bucket name is built from the team key (`${org}-team-${team}-${suffix}`), so the role is
        # structurally scoped to this team's own buckets — a team cannot name another team's bucket.
        inline_policies = {
          s3-access = jsonencode({
            Version = "2012-10-17"
            Statement = flatten([
              for suffix, s in cfg.aws.s3 : concat(
                [
                  { Effect = "Allow", Action = ["s3:ListBucket"], Resource = "arn:aws:s3:::${include.base.locals.org_name}-team-${team}-${suffix}" },
                  { Effect = "Allow", Action = ["s3:GetObject"], Resource = "arn:aws:s3:::${include.base.locals.org_name}-team-${team}-${suffix}/${s.prefix}*" },
                ],
                s.access == "readwrite" ? [
                  { Effect = "Allow", Action = ["s3:PutObject", "s3:DeleteObject"], Resource = "arn:aws:s3:::${include.base.locals.org_name}-team-${team}-${suffix}/${s.prefix}*" },
                ] : []
              )
            ])
          })
        }
      }
  })

  tags = include.base.locals.tags
}
