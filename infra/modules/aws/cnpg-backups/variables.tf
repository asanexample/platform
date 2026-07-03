variable "create" {
  description = "Create the backup bucket + per-cluster IAM/associations."
  type        = bool
  default     = true
}

variable "bucket_name" {
  description = "Name of the shared CNPG backup bucket (deterministic; per-cluster key prefixes live under it)."
  type        = string
}

variable "cluster_name" {
  description = "EKS cluster name for the Pod Identity associations (the hub the CNPG clusters run on)."
  type        = string
}

variable "clusters" {
  description = <<-EOT
    The CNPG clusters to grant backup access. Each gets its OWN key prefix (= name), its OWN least-privilege
    IAM role (scoped to that prefix), and a Pod Identity association binding the cluster's instance
    ServiceAccount to that role. `service_account` is the CNPG instance SA (defaults to the cluster name).
  EOT
  type = list(object({
    name            = string
    namespace       = string
    service_account = string
  }))
  default = []
}

variable "role_name_prefix" {
  description = "Prefix for the per-cluster IAM role names (role = <prefix>-<cluster>)."
  type        = string
  default     = "cnpg-backups"
}

variable "noncurrent_version_expiration_days" {
  description = "Expire noncurrent object versions after this many days (hygiene only — Barman owns backup retention via the ObjectStore retentionPolicy)."
  type        = number
  default     = 30
}

variable "force_destroy" {
  description = "Allow deleting a non-empty bucket on destroy. Keep false for a real backup store."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to the bucket, roles, and associations."
  type        = map(string)
  default     = {}
}
