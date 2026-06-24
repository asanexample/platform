variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "store_name" {
  description = "Name of the ClusterSecretStore resource"
  type        = string
  default     = "aws-secrets-manager"
}

variable "region" {
  description = "AWS region for the secret store backend"
  type        = string
}

variable "create_ssm_store" {
  description = "Also create a ClusterSecretStore for SSM Parameter Store"
  type        = bool
  default     = true
}
