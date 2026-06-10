# SOPS config-encryption key (ADR-066). Encrypts infra/live/aws/secrets.enc.yaml, which root.hcl + common.hcl
# decrypt inline at config-eval time. Decryption is gated entirely by this key policy: operators (SSO admins)
# may encrypt + decrypt; the ARC runner may decrypt only. Bootstrap-tier — every terragrunt run depends on it.

data "aws_caller_identity" "current" {}

data "aws_iam_policy_document" "key" {
  count = var.create ? 1 : 0

  # Standard root administration of the key (key admins manage policy/rotation via the account's IAM).
  statement {
    sid       = "EnableRootAdmin"
    effect    = "Allow"
    actions   = ["kms:*"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:root"]
    }
  }

  # Operators (SSO AdministratorAccess) — encrypt + decrypt, so `sops` editing works. Scoped to the SSO
  # reserved-role pattern via aws:PrincipalArn (same posture as PlatformDeployer's trust). Principals are the
  # account roots operators authenticate from; the condition narrows to the SSO admin role.
  statement {
    sid       = "OperatorsEncryptDecrypt"
    effect    = "Allow"
    actions   = ["kms:Encrypt", "kms:Decrypt", "kms:ReEncrypt*", "kms:GenerateDataKey*", "kms:DescribeKey"]
    resources = ["*"]
    principals {
      type        = "AWS"
      identifiers = var.operator_account_roots
    }
    condition {
      test     = "ArnLike"
      variable = "aws:PrincipalArn"
      values   = var.operator_principal_patterns
    }
  }

  # Decrypt-only principals (the ARC runner role) — reads config in CI, never edits it.
  dynamic "statement" {
    for_each = length(var.decrypt_principal_arns) > 0 ? [1] : []
    content {
      sid       = "DecryptOnly"
      effect    = "Allow"
      actions   = ["kms:Decrypt", "kms:DescribeKey"]
      resources = ["*"]
      principals {
        type        = "AWS"
        identifiers = var.decrypt_principal_arns
      }
    }
  }
}

resource "aws_kms_key" "sops" {
  count = var.create ? 1 : 0

  description             = "SOPS config encryption (ADR-066) — encrypts infra/live/aws/secrets.enc.yaml"
  deletion_window_in_days = var.deletion_window_in_days
  enable_key_rotation     = true
  policy                  = data.aws_iam_policy_document.key[0].json
  tags                    = var.tags

  # Bootstrap-floor: this key encrypts the committed secrets.enc.yaml, so destroying it would make EVERY
  # config load (root.hcl/common.hcl) undecryptable and brick a rebuild. It must survive teardown — like the
  # state backend (ADR-006). prevent_destroy is the seatbelt; teardown tooling must also exclude this unit.
  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_kms_alias" "sops" {
  count = var.create ? 1 : 0

  name          = "alias/${var.alias_name}"
  target_key_id = aws_kms_key.sops[0].key_id
}
