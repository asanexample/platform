variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Name of the EKS cluster (used for IAM role naming and txtOwnerId)"
  type        = string
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# IAM (EKS Pod Identity — ADR-047)
# ---------------------------------------------------------------------------

variable "route53_hosted_zone_arn" {
  description = "ARN of the Route53 hosted zone for DNS record management"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# external-dns configuration
# ---------------------------------------------------------------------------

variable "sources" {
  description = "Kubernetes resource types to watch for DNS records"
  type        = list(string)
  default     = ["gateway-httproute", "gateway-grpcroute", "gateway-tlsroute"]
}

variable "domain_filters" {
  description = "Limit DNS records to these domains"
  type        = list(string)
  default     = []
}

variable "policy" {
  description = "DNS record management policy (sync, upsert-only, create-only)"
  type        = string
  default     = "sync"
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Name of the Helm release"
  type        = string
  default     = "external-dns"
}

variable "helm_repository" {
  description = "Repository URL for the external-dns Helm chart"
  type        = string
  default     = "https://kubernetes-sigs.github.io/external-dns/"
}

variable "helm_chart" {
  description = "Name of the Helm chart"
  type        = string
  default     = "external-dns"
}

variable "helm_chart_version" {
  description = "Version of the external-dns Helm chart"
  type        = string
  default     = "1.16.1"
}

variable "namespace" {
  description = "Kubernetes namespace to install external-dns into"
  type        = string
  default     = "external-dns"
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
