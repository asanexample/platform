variable "create" {
  description = "Whether to create the SOPS KMS key."
  type        = bool
  default     = true
}

variable "alias_name" {
  description = "KMS alias (without the alias/ prefix)."
  type        = string
  default     = "platform-sops"
}

variable "operator_account_roots" {
  description = "Account-root ARNs of the accounts operators authenticate from (e.g. management + platform). Paired with operator_principal_patterns to scope to SSO admins."
  type        = list(string)
}

variable "operator_principal_patterns" {
  description = "ArnLike patterns (aws:PrincipalArn) for the operator principals allowed to encrypt + decrypt — typically the SSO AdministratorAccess reserved roles."
  type        = list(string)
}

variable "decrypt_principal_arns" {
  description = "Exact principal ARNs allowed to DECRYPT only (no encrypt) — e.g. the ARC runner role, which reads config in CI but never edits it."
  type        = list(string)
  default     = []
}

variable "deletion_window_in_days" {
  description = "KMS key deletion window."
  type        = number
  default     = 30
}

variable "tags" {
  description = "Tags applied to the key."
  type        = map(string)
  default     = {}
}
