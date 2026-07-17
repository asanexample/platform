variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "buckets" {
  description = <<-EOT
    Map of bucket name -> config. Each bucket is private (all public access blocked) and SSE-S3
    encrypted. reader_role_arns / writer_role_arns are granted via a bucket policy scoped to those exact
    role ARNs (least-privilege cross-account: tighter than an account :root grant). Cross-account S3
    access additionally requires the caller's own identity policy to allow it (granted on the team role).
    force_destroy allows a NON-EMPTY bucket to be deleted on destroy (empties it first). Keep false
    (the default) for durable stores; set true for rebuild-disposable content (e.g. a regenerable static
    site) so a teardown doesn't fail with BucketNotEmpty.
  EOT
  type = map(object({
    reader_role_arns = optional(list(string), [])
    writer_role_arns = optional(list(string), [])
    force_destroy    = optional(bool, false)
    tags             = optional(map(string), {})
  }))
  default = {}
}

variable "tags" {
  description = "Tags applied to all buckets"
  type        = map(string)
  default     = {}
}
