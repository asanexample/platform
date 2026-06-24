variable "create" {
  description = "Controls whether resources are created."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster name (Karpenter settings + IAM/tag scoping + Pod Identity association)."
  type        = string
}

variable "aws_region" {
  description = "AWS region."
  type        = string
  default     = "us-east-1"
}

variable "namespace" {
  description = "Namespace for the Karpenter controller."
  type        = string
  default     = "karpenter"
}

# ---------------------------------------------------------------------------
# Cluster plumbing (from the eks / node-groups / networking units)
# ---------------------------------------------------------------------------

variable "node_role_arn" {
  description = "ARN of the EKS node IAM role (created by eks-node-group). Karpenter nodes assume the SAME role; the EC2NodeClass references its name and the controller may PassRole it."
  type        = string
}

variable "cluster_security_group_id" {
  description = "The EKS cluster security group id — Karpenter nodes attach it (selected by id in the EC2NodeClass)."
  type        = string
}

variable "subnet_ids" {
  description = "Candidate node subnet ids (the cluster's kubernetes subnets). The EC2NodeClass selects these by id; restricted to one when single_az."
  type        = list(string)
}

variable "single_az" {
  description = "Pin Karpenter to a single AZ (matches the node groups' single-AZ dev placement) — selects only the first subnet."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# NodePool shape (per-cluster: conservative on platform, aggressive on preprod)
# ---------------------------------------------------------------------------

variable "node_arch" {
  description = "CPU architecture for provisioned nodes (`arm64` Graviton / `amd64`)."
  type        = string
  default     = "arm64"
}

variable "instance_families" {
  description = "Allowed EC2 instance families. Empty = a sensible default per node_arch."
  type        = list(string)
  default     = []
}

variable "min_instance_memory_mib" {
  description = "Exclude instance types smaller than this (MiB). Heavy per-node DaemonSets (Cilium, Beyla, Alloy, node-exporter) consume a fixed slab of every node's memory; too-small nodes exhaust it and the kubelet goes NotReady. 0 = no floor. Set ~6144 to require 8 GiB+ (t4g.large), matching the system node size."
  type        = number
  default     = 0
}

variable "capacity_types" {
  description = "Allowed capacity types — e.g. [\"on-demand\"] (platform, stateful-safe) or [\"spot\",\"on-demand\"] (preprod, cheap/ephemeral)."
  type        = list(string)
  default     = ["on-demand"]
}

variable "consolidation_policy" {
  description = "Karpenter disruption policy — `WhenEmpty` (only reclaim empty nodes; never disrupts running pods — use on the stateful platform cluster) or `WhenEmptyOrUnderutilized` (bin-pack + reclaim — cheaper, more churn — use on preprod)."
  type        = string
  default     = "WhenEmpty"

  validation {
    condition     = contains(["WhenEmpty", "WhenEmptyOrUnderutilized"], var.consolidation_policy)
    error_message = "consolidation_policy must be WhenEmpty or WhenEmptyOrUnderutilized."
  }
}

variable "consolidate_after" {
  description = "How long a node must be empty/underutilized before consolidation."
  type        = string
  default     = "1m"
}

variable "cpu_limit" {
  description = "NodePool ceiling on total provisioned vCPU (cost guardrail)."
  type        = number
  default     = 32
}

variable "memory_limit" {
  description = "NodePool ceiling on total provisioned memory (e.g. \"128Gi\")."
  type        = string
  default     = "128Gi"
}

variable "high_availability" {
  description = "Run 2 controller replicas (prod) vs 1 (dev)."
  type        = bool
  default     = false
}

# ---------------------------------------------------------------------------
# Helm
# ---------------------------------------------------------------------------

variable "helm_repository" {
  description = "Karpenter OCI Helm repository."
  type        = string
  default     = "oci://public.ecr.aws/karpenter"
}

variable "helm_chart_version" {
  description = "Karpenter chart version (pinned in _versions.hcl)."
  type        = string
  default     = "1.13.0"
}

variable "helm_timeout" {
  description = "Helm operation timeout (seconds)."
  type        = number
  default     = 300
}

variable "helm_wait" {
  description = "Wait for the controller release to become ready."
  type        = bool
  default     = true
}

variable "service_monitor_enabled" {
  description = "Scrape Karpenter's metrics via a ServiceMonitor (the observability stack picks them up)."
  type        = bool
  default     = true
}

variable "tags" {
  description = "AWS tags."
  type        = map(string)
  default     = {}
}
