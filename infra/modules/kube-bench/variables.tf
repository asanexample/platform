variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

variable "namespace" {
  description = "Dedicated namespace for the kube-bench scan Job (needs hostPID + read-only host mounts — kept out of tenant/PSA-restricted namespaces, mirroring the falco module)."
  type        = string
  default     = "kube-bench"
}

variable "image" {
  description = "kube-bench container image, pinned to an explicit tag (never :latest)."
  type        = string
  default     = "docker.io/aquasec/kube-bench:v0.15.6"

  validation {
    condition     = !endswith(var.image, ":latest") && length(regexall(":", var.image)) > 0
    error_message = "image must carry an explicit tag or digest (never :latest, never untagged)."
  }
}

variable "benchmark" {
  description = "CIS benchmark identifier kube-bench runs. EKS clusters can't self-detect the managed control plane, so the benchmark is passed explicitly (see kube-bench cfg/ for supported eks-* versions)."
  type        = string
  default     = "eks-1.8.0"
}

variable "targets" {
  description = "Comma-separated kube-bench targets. 'node' = kubelet/host-file CIS checks (needs the host mounts); 'policies' = in-cluster RBAC / NetworkPolicy checks (needs the read-only API access). 'managedservices'/'controlplane' are largely manual/AWS-side on EKS and are omitted by default (they'd need AWS creds)."
  type        = string
  default     = "node,policies"
}

variable "json_output" {
  description = "Emit findings as JSON to stdout (in addition to the human-readable summary) so a log pipeline (Loki/Alloy) can parse per-check results. Set false for summary-only logs."
  type        = bool
  default     = true
}

variable "schedule" {
  description = "CronJob schedule (UTC) for the scan. Default: daily at 06:00 UTC."
  type        = string
  default     = "0 6 * * *"
}

variable "successful_jobs_history_limit" {
  description = "How many succeeded scan Jobs to retain."
  type        = number
  default     = 3
}

variable "failed_jobs_history_limit" {
  description = "How many failed scan Jobs to retain (for triage)."
  type        = number
  default     = 3
}

variable "ttl_seconds_after_finished" {
  description = "Auto-delete each finished scan Job (succeeded or failed) after this many seconds, so a transient failure while the cluster is parked/scaled-down doesn't leave a stale Failed Job firing KubeJobFailed for days (failed Jobs have no completionTime, so the Kyverno succeeded-Job cleanup won't reap them)."
  type        = number
  default     = 86400
}

variable "resources" {
  description = "Resource requests/limits for the kube-bench container."
  type        = any
  default = {
    requests = { cpu = "50m", memory = "128Mi" }
    limits   = { memory = "256Mi" }
  }
}

variable "node_selector" {
  description = "nodeSelector for the scan pod. Defaults to Linux nodes."
  type        = map(string)
  default     = { "kubernetes.io/os" = "linux" }
}

variable "tolerations" {
  description = "Tolerations for the scan pod (list of { key, operator, value, effect }). Empty by default (scan lands on a normal workload node)."
  type = list(object({
    key      = optional(string)
    operator = optional(string)
    value    = optional(string)
    effect   = optional(string)
  }))
  default = []
}

variable "tags" {
  description = "Tags/labels to apply (sanitized to RFC-1123 for K8s labels)"
  type        = map(string)
  default     = {}
}
