variable "create" {
  description = "Whether to create resources"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Tailnet Settings
# ---------------------------------------------------------------------------

variable "https_enabled" {
  description = "Enable HTTPS certificates for tailnet devices (required for Tailscale Ingress TLS)"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# ACL Policy
# ---------------------------------------------------------------------------

variable "acl_policy" {
  description = "Tailscale ACL policy document (JSON or HuJSON)"
  type        = string
}

# ---------------------------------------------------------------------------
# OAuth Client
# ---------------------------------------------------------------------------

variable "create_oauth_client" {
  description = "Whether to create an OAuth client for the K8s operator"
  type        = bool
  default     = true
}

variable "oauth_client_tags" {
  description = "Tags that access tokens can assign to devices"
  type        = list(string)
  default     = ["tag:k8s-operator"]
}

variable "oauth_client_scopes" {
  description = "OAuth client permission scopes"
  type        = list(string)
  default = [
    "devices:core",
    "devices:routes",
    "auth_keys",
  ]
}

variable "oauth_client_description" {
  description = "Description for the OAuth client"
  type        = string
  default     = "K8s Operator managed by Terraform"
}

# ---------------------------------------------------------------------------
# AWS Secrets Manager
# ---------------------------------------------------------------------------

variable "write_to_secrets_manager" {
  description = "Write OAuth credentials to AWS Secrets Manager"
  type        = bool
  default     = true
}

variable "secrets_manager_name" {
  description = "Secrets Manager secret name for OAuth credentials"
  type        = string
  default     = "platform/tailscale/oauth"
}

variable "secrets_manager_recovery_window" {
  description = "Number of days to retain a deleted secret (0 = immediate deletion)"
  type        = number
  default     = 7
}

variable "tags" {
  description = "Tags to apply to AWS resources"
  type        = map(string)
  default     = {}
}
