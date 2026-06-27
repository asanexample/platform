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

variable "enable_gateway_api_plugin" {
  description = "Install the Argo Rollouts Gateway-API traffic-router plugin (ADR-056 D4) — drives weighted HTTPRoute canary on the Cilium Gateway. The controller downloads the binary at startup; harmless until a Rollout opts into trafficRouting.plugins.\"argoproj-labs/gatewayAPI\"."
  type        = bool
  default     = true
}

variable "enable_dashboard" {
  description = "Deploy the Argo Rollouts WEB UI (a Deployment + Service) — the live operator view of rollouts (canary progression, AnalysisRuns, promote/abort). Per-cluster: it shows THIS cluster's rollouts. Expose it with a gateway-config `rollouts` route. ⚠️ No built-in auth + write-capable SA — keep it Tailscale-internal."
  type        = bool
  default     = false
}

variable "gateway_api_plugin_version" {
  description = "Release tag of argoproj-labs/rollouts-plugin-trafficrouter-gatewayapi to load."
  type        = string
  default     = "v0.15.0"
}

variable "gateway_api_plugin_arch" {
  description = "CPU arch of the plugin binary — MUST match the controller's node arch (the platform runs Graviton/arm64)."
  type        = string
  default     = "arm64"
  validation {
    condition     = contains(["arm64", "amd64"], var.gateway_api_plugin_arch)
    error_message = "gateway_api_plugin_arch must be arm64 or amd64."
  }
}

variable "tags" {
  description = "Tags projected onto controller pod labels (RFC1123-sanitized)."
  type        = map(string)
  default     = {}
}
