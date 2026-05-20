variable "create" {
  description = "Whether to create the hosted zone"
  type        = bool
  default     = true
}

variable "domain_name" {
  description = "Domain name for the Route53 hosted zone"
  type        = string
}

variable "comment" {
  description = "Comment for the hosted zone"
  type        = string
  default     = "Managed by OpenTofu"
}

variable "force_destroy" {
  description = "Whether to destroy all records when destroying the zone"
  type        = bool
  default     = false
}

variable "caa_records" {
  description = "CAA records restricting which CAs can issue certificates (e.g. '0 issue \"letsencrypt.org\"')"
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
