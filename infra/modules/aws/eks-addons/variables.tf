variable "create" {
  description = "Whether to create resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider (required for addons that use IRSA)"
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "URL of the EKS OIDC provider without https:// prefix"
  type        = string
  default     = ""
}

variable "addons" {
  description = "Map of EKS managed add-ons to install. Key is addon name, value is config."
  type = map(object({
    addon_version            = optional(string)
    configuration_values     = optional(string)
    service_account_role_arn = optional(string)
    irsa = optional(object({
      service_account_name      = string
      service_account_namespace = string
      policy_arns               = list(string)
    }))
  }))
  default = {}
}

variable "create_default_storageclass" {
  description = "Create a gp3 StorageClass (via the EBS CSI driver) and mark it the cluster default. Needs the aws-ebs-csi-driver addon. Off by default; enable on clusters that need dynamic PVCs (e.g. the observability hub / Mimir, #102 P2)."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
