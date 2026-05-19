variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster to attach node groups to"
  type        = string
}

variable "node_groups" {
  description = "Managed node group definitions"
  type = map(object({
    subnet_ids      = list(string)
    instance_types  = list(string)
    desired_size    = number
    max_size        = number
    min_size        = number
    capacity_type   = optional(string, "ON_DEMAND")
    ami_type        = optional(string, "AL2023_x86_64_STANDARD")
    max_unavailable = optional(number, 1)
    labels          = optional(map(string), {})
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
