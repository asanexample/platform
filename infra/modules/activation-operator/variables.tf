variable "create" {
  description = "Master toggle for the add-on."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name. The Pod Identity role is named <cluster_name>-activation-operator, which the management activation-operator-identity-center role trusts."
  type        = string
}

variable "management_account_id" {
  description = "Management account ID — home of the activation-operator-identity-center role the operator assumes for the Identity Center plane."
  type        = string
}

variable "region" {
  description = "AWS region of the Identity Center instance (passed to the operator as --aws-region)."
  type        = string
  default     = "us-east-1"
}

variable "image" {
  description = "Fully-qualified, digest-pinned operator image (the operator-image.yml build output in platform ECR)."
  type        = string
}

variable "namespace" {
  description = "System namespace the operator runs in (NOT a tenant namespace)."
  type        = string
  default     = "activation-system"
}

variable "service_account" {
  description = "Operator ServiceAccount name (bound to the Pod Identity association)."
  type        = string
  default     = "activation-operator"
}

variable "replicas" {
  description = "Operator replica count (leader-elected; >1 gives standby failover)."
  type        = number
  default     = 1
}

variable "sync_period" {
  description = "Cache resync period — the safety net re-reconciling every Activation so a dropped expiry self-heals."
  type        = string
  default     = "2m"
}

variable "otel_endpoint" {
  description = "OTLP endpoint for the unified telemetry pipeline (traces+metrics → the cluster otel-collector). Empty disables export."
  type        = string
  default     = ""
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)."
  type        = number
  default     = 300
}

variable "helm_wait" {
  description = "Wait for the release to become ready (and make it atomic)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "Tags applied to the IAM role + Pod Identity association."
  type        = map(string)
  default     = {}
}
