variable "create" {
  description = "Whether to create the Argo Rollouts release (false = no-op, for destroy ordering)."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (for labelling / context only)."
  type        = string
}

variable "namespace" {
  description = "Namespace for the Argo Rollouts controller."
  type        = string
  default     = "argo-rollouts"
}

variable "helm_chart_version" {
  description = "argo/argo-rollouts Helm chart version (pinned in _versions.hcl)."
  type        = string
}

variable "replica_count" {
  description = "Argo Rollouts controller replicas. 1 for non-prod; 2+ for HA on the platform/hub cluster."
  type        = number
  default     = 1
}

variable "helm_wait" {
  description = "Wait for the release to become ready before returning."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags projected onto controller pod labels (RFC1123-sanitized)."
  type        = map(string)
  default     = {}
}
