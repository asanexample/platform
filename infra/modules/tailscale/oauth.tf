# Default OAuth locals — the live unit generates an oauth_override.tf that replaces these with values from AWS Secrets Manager
locals {
  oauth_client_id     = var.oauth_client_id
  oauth_client_secret = var.oauth_client_secret
}
