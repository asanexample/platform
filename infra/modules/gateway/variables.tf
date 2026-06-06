variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "domain" {
  description = "Base domain for the gateway (e.g. aws.refplat.org). The wildcard listener serves *.<domain>."
  type        = string
}

# ---------------------------------------------------------------------------
# ClusterIssuer
# ---------------------------------------------------------------------------

variable "cluster_issuer_name" {
  description = "Name of the cert-manager ClusterIssuer"
  type        = string
  default     = "letsencrypt-prod"
}

variable "letsencrypt_email" {
  description = "Email address for Let's Encrypt account registration"
  type        = string
}

variable "route53_hosted_zone_id" {
  description = "Route53 hosted zone ID for the DNS01 solver"
  type        = string
}

variable "route53_region" {
  description = "AWS region for Route53 API calls"
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Gateway
# ---------------------------------------------------------------------------

variable "gateway_name" {
  description = "Name of the Gateway resource. App HTTPRoutes attach to this via parentRef."
  type        = string
  default     = "platform-gateway"
}

variable "gateway_namespace" {
  description = "Namespace for the Gateway resource. App HTTPRoutes reference this namespace in their parentRef."
  type        = string
  default     = "default"
}

variable "internal" {
  description = "Use an internal NLB instead of internet-facing (requires VPN for access)"
  type        = bool
  default     = false
}
