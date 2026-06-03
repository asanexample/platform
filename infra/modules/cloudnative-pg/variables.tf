variable "create" {
  description = "Whether to install the CloudNativePG operator"
  type        = bool
  default     = true
}

variable "helm_release_name" {
  description = "Helm release name"
  type        = string
  default     = "cnpg"
}

variable "helm_repository" {
  description = "Helm chart repository"
  type        = string
  default     = "https://cloudnative-pg.github.io/charts"
}

variable "helm_chart" {
  description = "Helm chart name"
  type        = string
  default     = "cloudnative-pg"
}

variable "helm_chart_version" {
  description = "Helm chart version (pinned in _versions.hcl)"
  type        = string
}

variable "namespace" {
  description = "Namespace for the CloudNativePG operator"
  type        = string
  default     = "cnpg-system"
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Wait for the release to become ready"
  type        = bool
  default     = true
}

variable "replica_count" {
  description = "Operator controller replicas (leader-elected; 1 is fine for non-prod)"
  type        = number
  default     = 1
}

variable "webhook_host_network" {
  description = "Run the operator (admission webhook server) on hostNetwork so the EKS managed control plane can reach the webhook on the node VPC IP (required on the Cilium overlay / cluster-pool datapath). Moves the webhook to host port 9446 (off kyverno's 9443/9444)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags (rendered as pod labels)"
  type        = map(string)
  default     = {}
}
