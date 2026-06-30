variable "create" {
  description = "Whether to provision the directory database."
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Platform-infra namespace for the directory DB (NOT a tenant env — no platform.refplat.org/team label, so the tenant Kyverno policies don't apply)."
  type        = string
  default     = "platform-directory"
}

variable "db_cluster_name" {
  description = "CloudNativePG Cluster name."
  type        = string
  default     = "triage-copilot-db"
}

variable "consumer_namespace" {
  description = "The namespace allowed to reach the DB on 5432 (the triage agent's)."
  type        = string
  default     = "platform-agent-triage-copilot"
}

variable "extra_consumer_namespaces" {
  description = "Additional namespaces allowed to reach the DB on 5432 — e.g. the activation operator's, which writes the governance audit (ADR-088 §3.6)."
  type        = list(string)
  default     = []
}

variable "instances" {
  description = "CNPG instance count (1 = single; a rebuildable projection needs no HA)."
  type        = number
  default     = 1
}

variable "storage_size" {
  description = "CNPG volume size."
  type        = string
  default     = "5Gi"
}

variable "db_secret_name" {
  description = "Secrets Manager name for the published connection string (uri)."
  type        = string
  default     = "platform/triage-copilot/directory-db"
}

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window. 0 = force-delete (setup-friendly); raise for prod."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags applied to the generated Secrets Manager secret."
  type        = map(string)
  default     = {}
}

# Teardown finalizer-cleanup (mirrors the keycloak module) — clears CNPG finalizers so the namespace destroys
# cleanly (the pvc-protection finalizer otherwise hangs the destroy under node pressure).
variable "finalizer_clear_script" {
  description = "Path to scripts/k8s-finalizer-clear.sh (empty disables the teardown cleanup)."
  type        = string
  default     = ""
}

variable "cluster_name" {
  description = "EKS cluster name (for the teardown finalizer-cleanup)."
  type        = string
  default     = ""
}

variable "region" {
  description = "AWS region (for the teardown finalizer-cleanup)."
  type        = string
  default     = "us-east-1"
}

variable "deployer_role_arn" {
  description = "Deployer role ARN (for the teardown finalizer-cleanup)."
  type        = string
  default     = ""
}

variable "audit_writer_secret_name" {
  description = "Secrets Manager id for the activation-audit WRITER connection (the operator; INSERT-only on activation_audit). ADR-088 §3.6."
  type        = string
  default     = "platform/activation-operator/audit-writer-db"
}

variable "audit_reader_secret_name" {
  description = "Secrets Manager id for the activation-audit READER connection (Backstage; SELECT-only on activation_audit). ADR-088 §3.6."
  type        = string
  default     = "platform/backstage/audit-reader-db"
}
