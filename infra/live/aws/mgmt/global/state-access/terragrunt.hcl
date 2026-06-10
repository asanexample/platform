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
    TerraformStateAccess = {
      description          = "Cross-account access to S3 state bucket and DynamoDB lock table"
      max_session_duration = 3600 # 1 hour — sufficient for automated Terraform runs

      # Terragrunt assumes this role with a TAGGED session (same as PlatformDeployer), so the trust must allow
      # sts:TagSession in addition to sts:AssumeRole — else a tagged assume 403s on TagSession (e.g. the in-VPC
      # ARC runner reading dependency state). The caller also needs sts:TagSession (actions-runner-controller).
      trust_actions = ["sts:AssumeRole", "sts:TagSession"]

      trust_principals = {
        aws = [
          "arn:aws:iam::${include.base.locals.account_ids["platform"]}:root", # Platform account
          "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",     # Management account (self)
          "arn:aws:iam::${include.base.locals.account_ids["preprod"]}:root",  # Preprod account
        ]
      }

      managed_policies = []

      # Bucket and table names must match state-bootstrap configuration
      inline_policies = {
        state-access = jsonencode({
          Version = "2012-10-17"
          Statement = [
            {
              Sid    = "S3StateAccess"
              Effect = "Allow"
              Action = [
                "s3:GetObject",
                "s3:PutObject",
                "s3:DeleteObject",
                "s3:ListBucket",
              ]
              Resource = [
                "arn:aws:s3:::tfstate-mgmt-${include.base.locals.account_ids["mgmt"]}",
                "arn:aws:s3:::tfstate-mgmt-${include.base.locals.account_ids["mgmt"]}/*",
              ]
            },
            {
              Sid    = "DynamoDBLockAccess"
              Effect = "Allow"
              Action = [
                "dynamodb:GetItem",
                "dynamodb:PutItem",
                "dynamodb:DeleteItem",
              ]
              Resource = "arn:aws:dynamodb:us-east-1:${include.base.locals.account_ids["mgmt"]}:table/terraform-locks"
            },
          ]
        })
      }
    }
  }

  tags = include.base.locals.tags
}
