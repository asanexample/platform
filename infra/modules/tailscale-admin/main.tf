locals {
  create = var.create
}

# ---------------------------------------------------------------------------
# ACL Policy
# ---------------------------------------------------------------------------

resource "tailscale_acl" "this" {
  count = local.create ? 1 : 0

  acl                        = var.acl_policy
  overwrite_existing_content = true
}

# ---------------------------------------------------------------------------
# OAuth Client — for K8s operator authentication
# ---------------------------------------------------------------------------

resource "tailscale_oauth_client" "k8s_operator" {
  count = local.create && var.create_oauth_client ? 1 : 0

  description = var.oauth_client_description
  tags        = var.oauth_client_tags
  scopes      = var.oauth_client_scopes
}

# ---------------------------------------------------------------------------
# AWS Secrets Manager — store OAuth credentials for the K8s operator unit
# ---------------------------------------------------------------------------

resource "aws_secretsmanager_secret" "oauth" {
  count = local.create && var.create_oauth_client && var.write_to_secrets_manager ? 1 : 0

  name                    = var.secrets_manager_name
  recovery_window_in_days = var.secrets_manager_recovery_window
  tags                    = var.tags
}

resource "aws_secretsmanager_secret_version" "oauth" {
  count = local.create && var.create_oauth_client && var.write_to_secrets_manager ? 1 : 0

  secret_id = aws_secretsmanager_secret.oauth[0].id
  secret_string = jsonencode({
    clientId     = tailscale_oauth_client.k8s_operator[0].id
    clientSecret = tailscale_oauth_client.k8s_operator[0].key
  })
}
