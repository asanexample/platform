variable "create" {
  description = "Whether to create ArgoCD app resources"
  type        = bool
  default     = true
}

variable "tenants" {
  description = "Map of tenant names to their ArgoCD configuration"
  type = map(object({
    mode        = optional(string, "namespace")
    repo_url    = string
    repo_path   = optional(string, "k8s/preprod")
    repo_branch = optional(string, "main")
    namespace   = optional(string)
  }))
  default = {}
}

variable "cluster_name" {
  description = "Name of the target cluster in ArgoCD (e.g. 'preprod')"
  type        = string
}

variable "cluster_server" {
  description = "API server URL of the target cluster"
  type        = string
  default     = ""
}

variable "argocd_namespace" {
  description = "Namespace where ArgoCD is installed"
  type        = string
  default     = "argocd"
}

variable "auto_sync" {
  description = "Enable automated sync with self-heal and prune"
  type        = bool
  default     = true
}
