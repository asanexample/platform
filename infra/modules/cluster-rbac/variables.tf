variable "create" {
  description = "Whether to create the platform-operator RBAC resources"
  type        = bool
  default     = true
}

variable "group_name" {
  description = "Kubernetes group (mapped from the PlatformAdmin EKS access entry) to bind the platform-operator ClusterRole to"
  type        = string
  default     = "platform-operators"
}
