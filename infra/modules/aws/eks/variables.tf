variable "create" {
  description = "Whether to create resources in this module"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "kubernetes_version" {
  description = "Kubernetes version for the EKS cluster"
  type        = string
  default     = "1.35"
}

variable "subnet_ids" {
  description = "Subnet IDs for the EKS cluster ENIs"
  type        = list(string)
}

variable "additional_security_group_ids" {
  description = "Additional security group IDs to attach to the cluster (e.g. networking module's EKS SG)"
  type        = list(string)
  default     = []
}

variable "endpoint_private_access" {
  description = "Enable private API server endpoint"
  type        = bool
  default     = true
}

variable "endpoint_public_access" {
  description = "Enable public API server endpoint"
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to access the public API endpoint"
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enable_secrets_encryption" {
  description = "Enable KMS envelope encryption for Kubernetes secrets"
  type        = bool
  default     = true
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

variable "access_entries" {
  description = "IAM principal to Kubernetes access policy mappings"
  type = map(object({
    principal_arn = string
    policy_arn    = string
    type          = optional(string, "STANDARD")
    scope_type    = optional(string, "cluster")
    namespaces    = optional(list(string))
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
