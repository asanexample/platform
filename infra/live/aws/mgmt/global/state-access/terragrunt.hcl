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
      max_session_duration = 3600

      trust_principals = {
        aws = [
          "arn:aws:iam::829808296602:root",
          "arn:aws:iam::851725353202:root",
        ]
      }

      managed_policies = []

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
                "arn:aws:s3:::tfstate-mgmt-851725353202",
                "arn:aws:s3:::tfstate-mgmt-851725353202/*",
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
              Resource = "arn:aws:dynamodb:us-east-1:851725353202:table/terraform-locks"
            },
          ]
        })
      }
    }
  }

  tags = include.base.locals.tags
}
