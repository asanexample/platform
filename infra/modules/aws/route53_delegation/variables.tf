variable "create" {
  description = "Whether to create delegation records"
  type        = bool
  default     = true
}

variable "parent_zone_id" {
  description = "Route53 zone ID of the parent zone (e.g. aws.refplat.org)"
  type        = string
}

variable "delegations" {
  description = "Map of subdomain FQDN to list of nameservers (e.g. { 'preprod.aws.refplat.org' = ['ns-123.awsdns-01.com.', ...] })"
  type        = map(list(string))
  default     = {}
}

variable "ttl" {
  description = "TTL for NS delegation records"
  type        = number
  default     = 172800 # 48 hours — standard NS delegation TTL
}
