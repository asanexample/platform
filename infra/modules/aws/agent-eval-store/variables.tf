variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "bucket_name" {
  description = <<-EOT
    Deterministic S3 bucket name for the agent-eval corpus (e.g. platform-agent-eval-corpus).
    Deterministic (not a bucket_prefix) so the ARN is known at agent-claim-authoring time for the
    identity-based write grant (the XAgent's awsPermissions.policyStatements reference it).
  EOT
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name (3-63 chars, lowercase)."
  }
}

variable "kms_deletion_window_days" {
  description = "Waiting period (days) before the corpus CMK is deleted after scheduling."
  type        = number
  default     = 30
}

variable "object_lock_enabled" {
  description = <<-EOT
    Seam for S3 Object Lock (WORM). Deferred to the graduation slice (when the corpus actually gates
    autonomy, ADR-086); default false. Enabling it forces bucket replacement, so it must be set at
    creation time. The bucket-level default retention RULE is intentionally NOT declared here — only
    the capability is enabled — so the retention policy can be chosen when Object Lock is adopted.
  EOT
  type        = bool
  default     = false
}

variable "reader_role_arns" {
  description = <<-EOT
    Seam for future cross-account read access (e.g. a CI OIDC replay/grader role, ADR-080 D6). When
    non-empty, these principals get resource-based S3 read (GetObject/ListBucket) + KMS Decrypt on the
    corpus. Default empty: no reader role exists yet. The writer (the agent) is granted separately via
    its own identity policy (the XAgent claim), never here.
  EOT
  type        = list(string)
  default     = []
}

variable "transition_to_ia_days" {
  description = <<-EOT
    Optional lifecycle tiering: transition current corpus objects to STANDARD_IA after this many days
    (replay tolerates slow reads). 0 = disabled (default) — the corpus stays in Standard.
  EOT
  type        = number
  default     = 0
}

variable "force_destroy" {
  description = "Allow deleting a non-empty bucket on destroy. Keep false for the durable corpus; test fixtures may set true."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags applied to all resources"
  type        = map(string)
  default     = {}
}
