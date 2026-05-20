variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for IAM role naming)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# IRSA
# ---------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "ARN of the EKS OIDC provider for IRSA. Empty string disables IRSA."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "OIDC provider URL (without https:// prefix) for IRSA trust policy"
  type        = string
  default     = ""
}

variable "route53_hosted_zone_arn" {
  description = "ARN of the Route53 hosted zone for DNS01 challenge solving"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "cert-manager"
}

variable "helm_repository" {
  description = "Repository URL for the cert-manager Helm chart"
  type        = string
  default     = "https://charts.jetstack.io"
}

variable "helm_chart" {
  description = "Name of the Helm chart"
  type        = string
  default     = "cert-manager"
}

variable "helm_chart_version" {
  description = "Version of the cert-manager Helm chart"
  type        = string
  default     = "1.17.1"
}

variable "namespace" {
  description = "Kubernetes namespace to install cert-manager into"
  type        = string
  default     = "cert-manager"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Whether to wait for Helm release to complete"
  type        = bool
  default     = true
}
