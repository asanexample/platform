variable "create" {
  description = "Whether to create the delegation records"
  type        = bool
  default     = true
}

variable "cloudflare_zone_id" {
  description = "Cloudflare zone ID for the parent domain"
  type        = string
}

variable "subdomain" {
  description = "Subdomain to delegate (e.g. 'aws' for aws.refplat.org)"
  type        = string
}

variable "nameservers" {
  description = "List of authoritative nameservers for the subdomain"
  type        = list(string)
}
