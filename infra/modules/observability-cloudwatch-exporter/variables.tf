variable "create" {
  description = "Controls whether resources are created (cost_profile toggle — enable_cloud_metrics)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (for the Pod Identity association + resource naming)."
  type        = string
}

variable "namespace" {
  description = "Namespace to deploy into (the shared observability namespace; created by the observability module)."
  type        = string
  default     = "observability"
}

variable "aws_region" {
  description = "Region YACE signs STS against and scrapes by default."
  type        = string
  default     = "us-east-1"
}

variable "scrape_regions" {
  description = "AWS regions YACE discovers/scrapes resources in."
  type        = list(string)
  default     = ["us-east-1"]
}

variable "helm_repository" {
  description = "YACE chart repository (prometheus-community)."
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "prometheus-yet-another-cloudwatch-exporter"
}

variable "helm_chart_version" {
  description = "YACE chart version."
  type        = string
  default     = "0.46.0"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds."
  type        = number
  default     = 600
}

variable "tags" {
  description = "Tags/labels to apply."
  type        = map(string)
  default     = {}
}
