variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "name" {
  description = "Name prefix for DNS resources"
  type        = string
}

variable "dns_method" {
  description = "DNS resolution method: phz, resolver_outbound, or resolver_inbound"
  type        = string
  default     = "phz"

  validation {
    condition     = contains(["phz", "resolver_outbound", "resolver_inbound"], var.dns_method)
    error_message = "dns_method must be phz, resolver_outbound, or resolver_inbound."
  }
}

variable "vpc_id" {
  description = "VPC ID to associate PHZ or resolver endpoint with"
  type        = string
}

# --- PHZ variables ---

variable "phz_records" {
  description = "Map of name to PHZ config. Provide either static ips or eks_cluster_name for dynamic ENI lookup (requires eks_lookup_role_arn for cross-account)."
  type = map(object({
    domain              = string
    ips                 = optional(list(string), [])
    eks_cluster_name    = optional(string, "")
    eks_lookup_role_arn = optional(string, "")
    ttl                 = optional(number, 60)
  }))
  default = {}
}

# --- Resolver variables ---

variable "resolver_subnet_ids" {
  description = "Subnet IDs for resolver ENIs (min 2, different AZs). Used by both outbound and inbound."
  type        = list(string)
  default     = []
}

variable "resolver_allowed_cidrs" {
  description = "CIDRs allowed to query the inbound endpoint (e.g. platform VPC CIDR)"
  type        = list(string)
  default     = []
}

variable "forwarding_rules" {
  description = "Map of name to forwarding rule. Only used with resolver_outbound."
  type = map(object({
    domain     = string
    target_ips = list(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
