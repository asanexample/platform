variable "create" {
  description = "Whether to create resources"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "addons" {
  description = "Map of EKS managed add-ons to install. Key is addon name, value is config (version, configuration_values)."
  type = map(object({
    addon_version        = optional(string)
    configuration_values = optional(string)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to resources"
  type        = map(string)
  default     = {}
}
