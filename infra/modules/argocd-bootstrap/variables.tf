/**
 * # ArgoCD Bootstrap Module Variables
 */

variable "argocd_namespace" {
  description = "The namespace where ArgoCD is deployed"
  type        = string
}

variable "bootstrap_applications" {
  description = "List of applications to bootstrap with ArgoCD"
  type = list(object({
    name            = string
    namespace       = string
    repo_url        = string
    path            = optional(string, "")
    chart           = optional(string, "")
    target_revision = string
    helm_values     = optional(map(string), {})
    sync_wave       = optional(number, 0)
    self_heal       = optional(bool, true)
    prune           = optional(bool, true)
  }))
  default = []
}

variable "project" {
  description = "The ArgoCD project to use for applications"
  type        = string
  default     = "default"
}

variable "server" {
  description = "The Kubernetes server URL for ArgoCD to connect to"
  type        = string
  default     = "https://kubernetes.default.svc"
} 