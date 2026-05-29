# ---------------------------------------------------------------------------
# SCP 1: baseline-guardrails — Account & identity protection
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "baseline_guardrails" {
  count = local.create && var.service_control_policies == null ? 1 : 0

  statement {
    sid       = "DenyLeaveOrganization"
    effect    = "Deny"
    actions   = ["organizations:LeaveOrganization"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyRootUserActions"
    effect = "Deny"
    # Allow only GetSessionToken for root — required for MFA bootstrapping
    not_actions = ["sts:GetSessionToken"]
    resources   = ["*"]
    condition {
      test     = "StringLike"
      variable = "aws:PrincipalArn"
      values   = ["arn:aws:iam::*:root"]
    }
  }

  statement {
    sid       = "DenyRootAccessKeys"
    effect    = "Deny"
    actions   = ["iam:CreateAccessKey"]
    resources = ["arn:aws:iam::*:root"]
  }

  statement {
    sid       = "DenyRegionChanges"
    effect    = "Deny"
    actions   = ["account:EnableRegion", "account:DisableRegion"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid       = "DenyPasswordPolicyChanges"
    effect    = "Deny"
    actions   = ["iam:DeleteAccountPasswordPolicy", "iam:UpdateAccountPasswordPolicy"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid       = "ProtectOrganizationRole"
    effect    = "Deny"
    actions   = ["iam:AttachRolePolicy", "iam:DeleteRole", "iam:DeleteRolePermissionsBoundary", "iam:DeleteRolePolicy", "iam:DetachRolePolicy", "iam:PutRolePermissionsBoundary", "iam:PutRolePolicy", "iam:UpdateAssumeRolePolicy", "iam:UpdateRole", "iam:UpdateRoleDescription"]
    resources = ["arn:aws:iam::*:role/OrganizationAccountAccessRole"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 2: protect-security-services — Audit trail integrity
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "protect_security_services" {
  count = local.create && var.service_control_policies == null ? 1 : 0

  statement {
    sid    = "ProtectCloudTrail"
    effect = "Deny"
    actions = [
      "cloudtrail:StopLogging",
      "cloudtrail:DeleteTrail",
      "cloudtrail:UpdateTrail",
      "cloudtrail:PutEventSelectors",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid    = "ProtectConfig"
    effect = "Deny"
    actions = [
      "config:StopConfigurationRecorder",
      "config:DeleteConfigurationRecorder",
      "config:DeleteDeliveryChannel",
      "config:DeleteRetentionConfiguration",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid    = "ProtectGuardDuty"
    effect = "Deny"
    actions = [
      "guardduty:DeleteDetector",
      "guardduty:DisassociateFromMasterAccount",
      "guardduty:StopMonitoringMembers",
      "guardduty:UpdateDetector",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid    = "ProtectSecurityHub"
    effect = "Deny"
    actions = [
      "securityhub:DisableSecurityHub",
      "securityhub:BatchDisableStandards",
      "securityhub:DeleteMembers",
      "securityhub:DisassociateFromMasterAccount",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid       = "ProtectAccessAnalyzer"
    effect    = "Deny"
    actions   = ["access-analyzer:DeleteAnalyzer"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid       = "ProtectFlowLogs"
    effect    = "Deny"
    actions   = ["ec2:DeleteFlowLogs"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 3: enforce-encryption — Encryption at rest & instance security
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "enforce_encryption" {
  count = local.create && var.service_control_policies == null ? 1 : 0

  statement {
    sid       = "DenyDisableEbsDefault"
    effect    = "Deny"
    actions   = ["ec2:DisableEbsEncryptionByDefault"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid       = "DenyUnencryptedVolumes"
    effect    = "Deny"
    actions   = ["ec2:CreateVolume"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "ec2:Encrypted"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyUnencryptedEbsOnLaunch"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:volume/*"]
    condition {
      test     = "Bool"
      variable = "ec2:Encrypted"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyUnencryptedS3Uploads"
    effect    = "Deny"
    actions   = ["s3:PutObject"]
    resources = ["*"]
    condition {
      # Null test with "true" = deny when SSE header is ABSENT (forces explicit encryption)
      test     = "Null"
      variable = "s3:x-amz-server-side-encryption"
      values   = ["true"]
    }
  }

  statement {
    sid       = "DenyUnencryptedRds"
    effect    = "Deny"
    actions   = ["rds:CreateDBInstance"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "rds:StorageEncrypted"
      values   = ["false"]
    }
  }

  statement {
    sid       = "DenyUnencryptedRdsCluster"
    effect    = "Deny"
    actions   = ["rds:CreateDBCluster"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "rds:StorageEncrypted"
      values   = ["false"]
    }
  }

  statement {
    sid       = "ProtectKmsKeys"
    effect    = "Deny"
    actions   = ["kms:ScheduleKeyDeletion", "kms:DisableKey"]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid       = "EnforceIMDSv2"
    effect    = "Deny"
    actions   = ["ec2:RunInstances"]
    resources = ["arn:aws:ec2:*:*:instance/*"]
    condition {
      test     = "StringNotEquals"
      variable = "ec2:MetadataHttpTokens"
      values   = ["required"]
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 4: deny-regions — Region restriction with global service exemptions
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "deny_regions" {
  count = local.create && var.service_control_policies == null ? 1 : 0

  statement {
    sid    = "DenyNonAllowedRegions"
    effect = "Deny"
    not_actions = [
      "iam:*",
      "sts:*",
      "organizations:*",
      "route53:*",
      "route53domains:*",
      "cloudfront:*",
      "waf:*",
      "wafv2:*",
      "waf-regional:*",
      "shield:*",
      "globalaccelerator:*",
      "support:*",
      "health:*",
      "ce:*",
      "cur:*",
      "budgets:*",
      "billing:*",
      "account:*",
      "access-analyzer:*",
      "trustedadvisor:*",
      "sso:*",
      "pricing:*",
      "tag:*",
      "artifact:*",
      "tax:*",
      "freetier:*",
      "invoicing:*",
      "payments:*",
      "savingsplans:*",
    ]
    resources = ["*"]
    condition {
      test     = "StringNotEquals"
      variable = "aws:RequestedRegion"
      values   = var.allowed_regions
    }
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 5: protect-data-and-network — Public exposure prevention
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "protect_data_and_network" {
  count = local.create && var.service_control_policies == null ? 1 : 0

  statement {
    sid    = "ProtectS3PublicAccessBlock"
    effect = "Deny"
    actions = [
      "s3:PutAccountPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid    = "DenyDefaultVpc"
    effect = "Deny"
    actions = [
      "ec2:CreateDefaultVpc",
      "ec2:CreateDefaultSubnet",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid       = "DenyExternalSharing"
    effect    = "Deny"
    actions   = ["ram:CreateResourceShare"]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "ram:AllowsExternalPrincipals"
      values   = ["true"]
    }
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid    = "ProtectBackups"
    effect = "Deny"
    actions = [
      "glacier:DeleteArchive",
      "glacier:DeleteVault",
      "backup:DeleteBackupVault",
      "backup:DeleteBackupPlan",
      "backup:DeleteRecoveryPoint",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  # Tag integrity for per-team ABAC (#62): the `Team` tag must not be forgeable, or
  # the deny-other-teams developer policies could be bypassed by relabeling a
  # resource. Deny mutation of the Team tag except for platform/deployer roles AND
  # AWS service-linked roles (EKS/Auto Scaling tag/propagate tags onto the resources
  # they create — excluding them would break node provisioning/scaling).
  statement {
    sid    = "DenyTeamTagTampering"
    effect = "Deny"
    actions = [
      "ec2:CreateTags",
      "ec2:DeleteTags",
      "ecr:TagResource",
      "ecr:UntagResource",
      "iam:TagRole",
      "iam:UntagRole",
      "secretsmanager:TagResource",
      "secretsmanager:UntagResource",
    ]
    resources = ["*"]
    condition {
      test     = "ForAnyValue:StringEquals"
      variable = "aws:TagKeys"
      values   = ["Team"]
    }
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = concat(local.exempt_role_arns, ["arn:aws:iam::*:role/aws-service-role/*"])
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 6: require-tagging — Dynamic per var.required_tags
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "require_tagging" {
  count = local.create && var.service_control_policies == null ? 1 : 0

  dynamic "statement" {
    for_each = var.required_tags
    content {
      sid    = "RequireTag${replace(statement.value, "/[^a-zA-Z0-9]/", "")}"
      effect = "Deny"
      actions = [
        "ec2:RunInstances",
        "s3:CreateBucket",
        "rds:CreateDBInstance",
      ]
      resources = ["*"]
      condition {
        test     = "Null"
        variable = "aws:RequestTag/${statement.value}"
        values   = ["true"]
      }
      condition {
        test     = "ArnNotLike"
        variable = "aws:PrincipalArn"
        values   = local.exempt_role_arns
      }
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 7: restrict-iam-users — Force federation
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "restrict_iam_users" {
  count = local.create && var.service_control_policies == null ? 1 : 0

  statement {
    sid    = "DenyIamUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateLoginProfile",
      "iam:CreateAccessKey",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }

  statement {
    sid    = "DenyUserPolicyAttachment"
    effect = "Deny"
    actions = [
      "iam:AttachUserPolicy",
      "iam:PutUserPolicy",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }
}

# ---------------------------------------------------------------------------
# SCP 8: hipaa-eligible-services — HIPAA service allowlist (optional)
# ---------------------------------------------------------------------------

data "aws_iam_policy_document" "hipaa_eligible_services" {
  count = local.create && var.service_control_policies == null && var.enable_hipaa_scp ? 1 : 0

  statement {
    sid    = "DenyNonHipaaServices"
    effect = "Deny"
    not_actions = [
      "a4b:*",
      "acm:*",
      "amplify:*",
      "apigateway:*",
      "appflow:*",
      "appmesh:*",
      "appstream:*",
      "appsync:*",
      "athena:*",
      "autoscaling:*",
      "backup:*",
      "batch:*",
      "chime:*",
      "cloud9:*",
      "cloudformation:*",
      "cloudfront:*",
      "cloudhsm:*",
      "cloudtrail:*",
      "cloudwatch:*",
      "codebuild:*",
      "codecommit:*",
      "codedeploy:*",
      "codepipeline:*",
      "cognito-identity:*",
      "cognito-idp:*",
      "comprehend:*",
      "comprehendmedical:*",
      "config:*",
      "connect:*",
      "databrew:*",
      "datapipeline:*",
      "datasync:*",
      "directconnect:*",
      "dms:*",
      "ds:*",
      "dynamodb:*",
      "ebs:*",
      "ec2:*",
      "ecr:*",
      "ecs:*",
      "eks:*",
      "elasticache:*",
      "elasticbeanstalk:*",
      "elasticfilesystem:*",
      "elasticloadbalancing:*",
      "elasticmapreduce:*",
      "es:*",
      "events:*",
      "execute-api:*",
      "firehose:*",
      "fis:*",
      "fsx:*",
      "glacier:*",
      "globalaccelerator:*",
      "glue:*",
      "greengrass:*",
      "groundstation:*",
      "guardduty:*",
      "healthlake:*",
      "iam:*",
      "inspector:*",
      "iot:*",
      "iotevents:*",
      "iotsitewise:*",
      "kafka:*",
      "kendra:*",
      "kinesis:*",
      "kinesisanalytics:*",
      "kinesisvideo:*",
      "kms:*",
      "lambda:*",
      "lex:*",
      "logs:*",
      "macie2:*",
      "managedblockchain:*",
      "mq:*",
      "neptune-db:*",
      "network-firewall:*",
      "organizations:*",
      "outposts:*",
      "polly:*",
      "qldb:*",
      "quicksight:*",
      "rds:*",
      "rds-data:*",
      "redshift:*",
      "rekognition:*",
      "robomaker:*",
      "route53:*",
      "route53resolver:*",
      "s3:*",
      "sagemaker:*",
      "secretsmanager:*",
      "securityhub:*",
      "servicecatalog:*",
      "ses:*",
      "shield:*",
      "sns:*",
      "sqs:*",
      "ssm:*",
      "sso:*",
      "states:*",
      "storagegateway:*",
      "sts:*",
      "swf:*",
      "textract:*",
      "timestream:*",
      "transcribe:*",
      "transfer:*",
      "translate:*",
      "waf:*",
      "waf-regional:*",
      "wafv2:*",
      "workdocs:*",
      "worklink:*",
      "workspaces:*",
      "xray:*",
    ]
    resources = ["*"]
    condition {
      test     = "ArnNotLike"
      variable = "aws:PrincipalArn"
      values   = local.exempt_role_arns
    }
  }
}
