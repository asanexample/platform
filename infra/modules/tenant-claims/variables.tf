variable "create" {
  description = "Whether to create resources in this module."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Namespace the Helm release object lives in (the XTenant claims themselves are cluster-scoped). crossplane-system keeps it alongside the control plane."
  type        = string
  default     = "crossplane-system"
}

variable "tenants" {
  description = "Map of claim name => XTenant spec (team, hostnames, resourceQuota, apps, aws, developerAccess, complianceTier). Each entry is rendered verbatim as an XTenant claim — the unit's HCL is the source of truth for each tenant."
  type        = any
  default     = {}
}

variable "helm_wait" {
  description = "Wait for the Helm release to apply. XTenant readiness is reconciled asynchronously by Crossplane (helm has nothing to block on), so this just gates the apply itself."
  type        = bool
  default     = true
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)."
  type        = number
  default     = 300
}
