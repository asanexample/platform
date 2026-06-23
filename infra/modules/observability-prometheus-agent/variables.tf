variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "Spoke EKS cluster name (resource naming / fallback cluster label)."
  type        = string
}

variable "cluster_label" {
  description = "Value of the `cluster` external label stamped on every series (so the hub can isolate this spoke, e.g. `up{cluster=\"preprod\"}`). Falls back to cluster_name when empty."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region (informational; the agent holds no AWS creds — it only scrapes + remote_writes)."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace to deploy the agent into. Created here (NOT by the chart) with PSA `privileged` (node-exporter needs host access) + a default-deny-ingress NetworkPolicy."
  type        = string
  default     = "observability"
}

# ---------------------------------------------------------------------------
# Remote write (the hub-and-spoke write path, #102 P10)
# ---------------------------------------------------------------------------

variable "remote_write_url" {
  description = "Hub Mimir spoke-ingest endpoint, e.g. https://preprod-mimir.aws.refplat.org/api/v1/push. The hub Gateway force-sets X-Scope-OrgID per-hostname, so the agent deliberately sends NO tenant header (it would be overwritten). Empty disables remote_write (agent buffers locally only)."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_release_name" {
  description = "Helm release name (also the chart fullname prefix)."
  type        = string
  default     = "prometheus-agent"
}

variable "helm_repository" {
  description = "Helm repository URL."
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Helm chart name. kube-prometheus-stack in agent mode — same chart as the hub, so metric names/labels match and the hub dashboards work for this spoke."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "helm_chart_version" {
  description = "kube-prometheus-stack chart version (pin from _versions.hcl; reuses the hub's pin)."
  type        = string
  default     = "86.1.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds). Generous: the Prometheus StatefulSet binds a WaitForFirstConsumer WAL PVC on first schedule."
  type        = number
  default     = 900
}

variable "helm_wait" {
  description = "Wait for the release to become ready."
  type        = bool
  default     = true
}

variable "high_availability" {
  description = "HA sizing: 2 agent replicas + hard pod anti-affinity. false = single replica (reference spoke)."
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass for the agent's remote-write WAL PVC (buffers samples across pod restarts during a hub outage). Empty string (default) = ephemeral emptyDir WAL — portable across clusters with no StorageClass dependency, which is the right default for a lightweight spoke. Set to a class that EXISTS on the spoke cluster (e.g. gp2/gp3) for a durable WAL."
  type        = string
  default     = ""
}

variable "wal_size" {
  description = "Size of the agent's WAL PVC (only used when storage_class is set)."
  type        = string
  default     = "5Gi"
}

variable "tags" {
  description = "Tags sanitized into K8s labels on the namespace."
  type        = map(string)
  default     = {}
}
