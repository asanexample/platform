variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (for resource naming / labels)."
  type        = string
}

variable "aws_region" {
  description = "AWS region (for the Alertmanager → SNS sigv4 signer)."
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Helm (kube-prometheus-stack)
# ---------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace for the observability hub. Created by this module (not the chart) so it carries the right Pod Security Admission label for node-exporter."
  type        = string
  default     = "observability"
}

variable "helm_release_name" {
  description = "Helm release name. Pinned so the Grafana Service (<release>-grafana) and the Alertmanager ServiceAccount (<release>-alertmanager) names are deterministic for the gateway route and IRSA."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "helm_repository" {
  description = "kube-prometheus-stack chart repository."
  type        = string
  default     = "https://prometheus-community.github.io/helm-charts"
}

variable "helm_chart" {
  description = "Chart name."
  type        = string
  default     = "kube-prometheus-stack"
}

variable "helm_chart_version" {
  description = "kube-prometheus-stack chart version (latest GA — resolve at apply time)."
  type        = string
  default     = "86.1.0"
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds."
  type        = number
  default     = 900
}

variable "helm_wait" {
  description = "Whether to wait for the Helm release to become ready."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Sizing / HA (per-unit toggle, mirrors the argocd module)
# ---------------------------------------------------------------------------

variable "high_availability" {
  description = "HA mode: Prometheus ×2, Alertmanager ×3, Grafana ×2 with anti-affinity + PDB. false = single-replica (cost-optimized) — fine for the reference clusters. Needs >=3 nodes across >=2-3 AZs when true."
  type        = bool
  default     = false
}

variable "prometheus_retention" {
  description = "Local Prometheus retention. Interim only — Mimir becomes the durable store at P2; kept short here."
  type        = string
  default     = "15d"
}

variable "use_persistent_storage" {
  description = "Back Prometheus/Alertmanager with PVCs (needs a default StorageClass). false = emptyDir (acceptable for the interim P1 local Prometheus; Mimir is durable from P2)."
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass for Prometheus/Alertmanager PVCs when use_persistent_storage = true."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Mimir remote_write (#102 P2) — durable long-range metrics store
# ---------------------------------------------------------------------------

variable "mimir_remote_write_url" {
  description = "Mimir push endpoint for Prometheus remote_write (e.g. http://mimir-gateway.observability.svc/api/v1/push). Empty = no remote_write (P1 behaviour). When set, the bundled Prometheus datasource is no longer Grafana's default (the Mimir datasource takes over)."
  type        = string
  default     = ""
}

variable "mimir_tenant_id" {
  description = "X-Scope-OrgID the hub's own metrics are written under (and queried with)."
  type        = string
  default     = "platform"
}

# ---------------------------------------------------------------------------
# IRSA (P1: Alertmanager → SNS publish only)
# ---------------------------------------------------------------------------

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN, for the Alertmanager IRSA trust policy."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (no https:// prefix)."
  type        = string
  default     = ""
}

variable "alerts_topic_arn" {
  description = "SNS topic ARN for critical alerts. When set (with OIDC), the Alertmanager SA gets an IRSA role with sns:Publish on it and the Alertmanager config gains an sns_configs receiver."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Grafana admin (External Secrets; SSO is a fast-follow)
# ---------------------------------------------------------------------------

variable "secret_path_prefix" {
  description = "Secrets Manager path prefix for the generated Grafana admin credential (stored at <prefix>/observability/grafana-admin for human retrieval; the k8s Secret is created directly by TF since the password is TF-generated)."
  type        = string
  default     = "platform"
}

variable "grafana_hostname" {
  description = "External hostname Grafana is served at (gateway HTTPRoute). Sets grafana.ini root_url and the cookie domain."
  type        = string
  default     = "grafana.aws.refplat.org"
}

# ---------------------------------------------------------------------------
# Network policy
# ---------------------------------------------------------------------------

variable "gateway_namespace" {
  description = "Namespace of the Gateway-API gateway (Envoy) allowed to reach Grafana ingress. Empty = allow ingress to Grafana from all namespaces (still default-deny for the rest of the ns)."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags/labels to apply (sanitized to RFC-1123 for K8s labels)."
  type        = map(string)
  default     = {}
}
