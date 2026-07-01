variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (for resource naming / labels)."
  type        = string
}

variable "cluster_label" {
  description = "Value of the `cluster` external label stamped on every metric — the multi-cluster dimension. Use a clean, consistent name matching the tenant/env (e.g. `platform`), so the single pane reads `platform`/`preprod`, not the raw EKS cluster IDs. Empty falls back to cluster_name (the EKS cluster ID)."
  type        = string
  default     = ""
}

variable "aws_region" {
  description = "AWS region (for the Alertmanager → SNS sigv4 signer)."
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Teardown — robust cluster auth for the destroy-time namespace drain.
# Like backstage, the namespace hung ~5m in Terminating (deadline exceeded)
# on Succeeded prometheus/mimir/alertmanager pods (no finalizer, kubelet never
# confirmed) pinning their pvc-protection PVCs. A when=destroy step deletes the
# stateful workloads + force-clears pods/PVCs first via scripts/k8s-finalizer-clear.sh.
# ---------------------------------------------------------------------------

variable "deployer_role_arn" {
  description = "IAM role ARN to assume for the destroy-time namespace drain (the PlatformDeployer)"
  type        = string
  default     = ""
}

variable "finalizer_clear_script" {
  description = "Non-empty enables the destroy-time teardown cleanup script. Only checked for non-emptiness — the script itself is resolved at run time via the checkout's own `git rev-parse --show-toplevel`, not this value, so a worktree's different absolute path can't force a spurious null_resource replace. Kept as a path-shaped string for unit-wiring compatibility (units still pass get_repo_root())."
  type        = string
  default     = ""
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
  description = "Helm release name. Pinned so the Grafana Service (<release>-grafana) and the Alertmanager ServiceAccount (<release>-alertmanager) names are deterministic for the gateway route and the Pod Identity association (ADR-047)."
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
  description = "Back Prometheus/Alertmanager/Grafana with PVCs (needs a default StorageClass). false = emptyDir/ephemeral (acceptable for the interim P1 local Prometheus; Mimir is durable from P2; Grafana's SQLite state — service accounts, API tokens, UI-created alert rules — is wiped on every pod restart without this, #1070)."
  type        = bool
  default     = false
}

variable "storage_class" {
  description = "StorageClass for Prometheus/Alertmanager/Grafana PVCs when use_persistent_storage = true."
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
# IAM (P1: Alertmanager → SNS publish via EKS Pod Identity, ADR-047)
# ---------------------------------------------------------------------------


variable "alerts_topic_arn" {
  description = "SNS topic ARN for critical alerts. When set, the Alertmanager SA gets a role with sns:Publish (bound via EKS Pod Identity) and the Alertmanager config gains an sns_configs receiver."
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

variable "secret_recovery_window_days" {
  description = "Secrets Manager recovery window for the generated Grafana admin secret. 0 = force-delete (setup-friendly); raise for prod."
  type        = number
  default     = 0
}

variable "tags" {
  description = "Tags/labels to apply (sanitized to RFC-1123 for K8s labels)."
  type        = map(string)
  default     = {}
}

# ---------------------------------------------------------------------------
# Slack alerting (Alertmanager Slack receiver via an External-Secrets-synced webhook)
# ---------------------------------------------------------------------------

variable "slack_webhook_secret_name" {
  description = "AWS Secrets Manager secret name holding the Slack incoming-webhook URL (JSON property 'url'). Empty disables the Slack receiver (SNS-only). Synced to Alertmanager via External Secrets — never enters Terraform state or helm values."
  type        = string
  default     = ""
}

variable "slack_channel" {
  description = "Slack channel for alerts (the incoming webhook is bound to its own channel; this is informational/override)."
  type        = string
  default     = "#platform-alerts"
}

variable "triage_webhook_url" {
  description = "ADR-082: the triage agent's in-cluster webhook URL (e.g. http://triage-copilot-server.platform-agent-triage-copilot.svc.cluster.local/webhook). When set, a curated alert subset (critical) is fanned to the agent ADDITIVELY (continue=true, the alert still reaches SNS/Slack). Empty disables the triage receiver/route."
  type        = string
  default     = ""
}

variable "pagerduty_routing_key_secret_name" {
  description = "AWS Secrets Manager secret name holding the PagerDuty Events API v2 routing/integration key (JSON property 'routingKey'). Empty disables the PagerDuty receiver. Synced to Alertmanager via External Secrets — never enters Terraform state or helm values. Critical alerts page PagerDuty."
  type        = string
  default     = ""
}

variable "secret_store_name" {
  description = "Name of the External Secrets ClusterSecretStore (AWS Secrets Manager)."
  type        = string
  default     = "aws-secrets-manager"
}

# ---------------------------------------------------------------------------
# P5a — Cloud-resource metrics: Grafana CloudWatch datasource
# ---------------------------------------------------------------------------

variable "cloudwatch_enabled" {
  description = "Add a Grafana CloudWatch datasource (query-time, zero-storage AWS-resource metrics) + grant the Grafana ServiceAccount CloudWatch read via EKS Pod Identity. Covers NLB/S3/TGW/NAT/Route53/EKS etc. with no exporter. #102 P5a."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Grafana SSO via Keycloak OIDC (#592, ADR-053/059 — same pattern as ArgoCD/Backstage)
# ---------------------------------------------------------------------------

variable "grafana_oidc_issuer" {
  description = "Keycloak OIDC issuer URL (e.g. https://keycloak.aws.refplat.org/realms/platform). Empty disables Grafana SSO (admin-password only)."
  type        = string
  default     = ""
}

variable "grafana_oidc_client_id" {
  description = "Grafana OIDC client_id in Keycloak."
  type        = string
  default     = "grafana"
}

variable "grafana_oidc_secret_manager_key" {
  description = "AWS Secrets Manager key holding the Grafana OIDC client secret (keycloak-config writes platform/keycloak/grafana-oidc, JSON property `client-secret`). Synced to a K8s secret via ExternalSecret, injected as GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET."
  type        = string
  default     = ""
}

variable "grafana_oidc_role_attribute_path" {
  description = "Grafana role mapping (JMESPath over the token's `groups` claim). Default: platform-admins → Admin, any other authenticated user → Viewer. Per-team Editor scoping is P13 (#590)."
  type        = string
  default     = "contains(groups[*], 'platform-admins') && 'Admin' || 'Viewer'"
}

variable "oidc_gateway_alias_host" {
  description = "Split-horizon host-alias: the OIDC issuer hostname (keycloak.aws.refplat.org) pinned to the Cilium Gateway Envoy ClusterIP, so Grafana's backend token/userinfo calls reach Keycloak via the gateway directly — NOT the internal NLB (which a pod can't reliably hairpin to). Mirrors Backstage. Empty disables the alias."
  type        = string
  default     = ""
}

variable "gateway_service_name" {
  description = "Cilium gateway LoadBalancer Service whose ClusterIP backs oidc_gateway_alias_host."
  type        = string
  default     = "cilium-gateway-platform-gateway"
}

variable "gateway_service_namespace" {
  description = "Namespace of the Cilium gateway Service."
  type        = string
  default     = "default"
}
