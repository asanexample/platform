/**
 * # ArgoCD Module Variables
 */

variable "create_namespace" {
  description = "Whether to create the ArgoCD namespace"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "The namespace to deploy ArgoCD into"
  type        = string
  default     = "argocd"
}

variable "namespace_labels" {
  description = "Labels to apply to the ArgoCD namespace"
  type        = map(string)
  default     = {}
}

variable "release_name" {
  description = "The name of the Helm release"
  type        = string
  default     = "argocd"
}

variable "chart_version" {
  description = "The version of the ArgoCD Helm chart to deploy"
  type        = string
  default     = "5.51.4" # Update this to the latest stable version as needed
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 1200
}

variable "domain" {
  description = "The domain to use for ArgoCD"
  type        = string
  default     = ""
}

variable "high_availability" {
  description = "Whether to deploy ArgoCD in high availability mode"
  type        = bool
  default     = false
}

variable "insecure" {
  description = "Whether to run the ArgoCD server in insecure mode"
  type        = bool
  default     = false
}

variable "service_type" {
  description = "The Kubernetes service type to use for the ArgoCD server"
  type        = string
  default     = "ClusterIP"
}

variable "enable_dex" {
  description = "Whether to enable the Dex server for SSO"
  type        = bool
  default     = true
}

variable "enable_notifications" {
  description = "Whether to enable the ArgoCD notifications controller"
  type        = bool
  default     = true
}

variable "admin_password" {
  description = "The password to use for the admin user. If not set, a random password will be generated."
  type        = string
  default     = ""
  sensitive   = true
}

variable "additional_set_values" {
  description = "Additional values to set on the Helm release"
  type = list(object({
    name  = string
    value = string
    type  = optional(string)
  }))
  default = []
} 