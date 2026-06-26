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
  description = "Enable the public API server endpoint. Defaults to false — private-only is the house policy (ADR-010); reach the API over Tailscale/SSM. Set true only deliberately (and narrow public_access_cidrs)."
  type        = bool
  default     = false
}

variable "public_access_cidrs" {
  description = "CIDR blocks allowed to reach the public API endpoint. Only applies when endpoint_public_access = true — narrow this to operator IPs; do NOT rely on the open default if you enable public access."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

variable "enabled_cluster_log_types" {
  description = "EKS control plane log types to enable"
  type        = list(string)
  default     = ["api", "audit", "authenticator", "controllerManager", "scheduler"]
}

variable "enable_secrets_encryption" {
  description = "Enable KMS envelope encryption for Kubernetes secrets"
  type        = bool
  default     = true
}

variable "access_entries" {
  description = "IAM principal to Kubernetes access policy mappings"
  type = map(object({
    principal_arn = string
    # Optional: when set, an AWS-managed access policy is associated (e.g. AmazonEKSEditPolicy).
    # When null, the entry maps the principal to kubernetes_groups for cluster-managed RBAC instead.
    policy_arn        = optional(string)
    type              = optional(string, "STANDARD")
    scope_type        = optional(string, "cluster")
    namespaces        = optional(list(string))
    kubernetes_groups = optional(list(string), [])
  }))
  default = {}
}

variable "eks_addons" {
  description = "EKS managed add-ons to install (e.g. coredns, kube-proxy)"
  type = map(object({
    most_recent = optional(bool, true)
  }))
  default = {}
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
