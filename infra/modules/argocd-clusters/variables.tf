variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "ArgoCD namespace where cluster secrets are created"
  type        = string
  default     = "argocd"
}

variable "clusters" {
  description = "Map of remote clusters to register with ArgoCD"
  type = map(object({
    server  = string
    ca_data = string
    aws_auth = optional(object({
      cluster_name = string
      role_arn     = string
    }))
  }))
  default = {}
}
