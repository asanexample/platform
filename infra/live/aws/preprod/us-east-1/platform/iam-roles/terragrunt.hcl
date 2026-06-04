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

  # Per-team developer + Pod Identity workload roles (DeveloperAccess-<team>, Pod-team-<team>) are now
  # provisioned by the Tenant Composition (iam.aws.upbound.io), not here — all teams migrated (BACK stack P3,
  # #174). This unit retains only the static platform roles below.
  roles = {
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

    # Cross-account READ-ONLY cluster access for the Backstage portal (platform hub). The portal's EKS Pod
    # Identity reader role on the platform cluster assumes this to surface preprod workloads in the catalog
    # (Kubernetes plugin, 2.4a). View-only — the eks unit grants it AmazonEKSViewPolicy (excludes Secrets).
    Backstage = {
      description = "Cross-account read-only cluster access for the Backstage portal (platform hub)"

      # Backstage's k8s AWS auth assumes this role with a tagged session, so the trust must allow TagSession
      # in addition to AssumeRole (the reader role's identity policy grants the matching permissions).
      trust_actions = ["sts:AssumeRole", "sts:TagSession"]

      trust_principals = {
        aws = ["arn:aws:iam::${include.base.locals.account_ids["platform"]}:root"] # Platform account
      }

      # Only the Backstage reader role from the platform EKS cluster (name_prefix platform-use1-eks-backstage-).
      trust_conditions = [
        {
          test     = "ArnLike"
          variable = "aws:PrincipalArn"
          values   = ["arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/platform-use1-eks-backstage-*"]
        },
      ]

      managed_policies = []
    }

  }

  tags = include.base.locals.tags
}
