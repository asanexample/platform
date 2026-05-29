variable "create" {
  description = "Controls whether resources should be created"
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Policy behaviour
# ---------------------------------------------------------------------------

variable "validation_failure_action" {
  description = "How validate policies behave on a violation. 'Audit' records a PolicyReport but admits the resource (lockout-safe rollout); 'Enforce' rejects it at admission. Drives both the policy action and the generated webhook failurePolicy (Audit->Ignore, Enforce->Fail)."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Enforce"], var.validation_failure_action)
    error_message = "validation_failure_action must be either \"Audit\" or \"Enforce\"."
  }
}

variable "compliance_tier" {
  description = "Compliance tier driving policy strictness (ADR-013). 'restricted'-grade pod policies (read-only rootfs, restricted securityContext) are only enforced for hipaa/pci."
  type        = string
  default     = "standard"

  validation {
    condition     = contains(["standard", "hipaa", "pci"], var.compliance_tier)
    error_message = "compliance_tier must be one of: standard, hipaa, pci."
  }
}

variable "allowed_registries" {
  description = "Container image registry prefixes admitted cluster-wide (e.g. the platform ECR host). The cluster-wide floor; per-tenant scoping is layered on top via tenant_registry_map."
  type        = list(string)
  default     = []
}

variable "tenant_registry_map" {
  description = "Map of tenant key -> allowed image prefix for that tenant's namespace (team-<key>). Supplied by the terragrunt unit from teams.hcl; the module holds no team-specific data."
  type        = map(string)
  default     = {}
}

variable "exclude_namespaces" {
  description = "Infrastructure namespaces excluded from tenant-targeted and cluster-scoped policies so Kyverno never gates platform/system workloads."
  type        = list(string)
  default = [
    "kube-system",
    "kube-node-lease",
    "kube-public",
    "kyverno",
    "cert-manager",
    "external-secrets",
    "external-dns",
    "argocd",
    "tailscale",
  ]
}

variable "exclude_principals" {
  description = "Principal (username) wildcards excluded from cluster-scoped policies (RBAC/registry floor) so platform controllers can reconcile addons. Defaults cover the Terraform deployer, ArgoCD, and Kubernetes service controllers."
  type        = list(string)
  default = [
    "system:serviceaccount:argocd:*",
    "system:serviceaccount:kube-system:*",
    "system:nodes:*",
    "system:kube-controller-manager",
  ]
}

variable "tenant_namespace_label" {
  description = "Namespace label that marks tenant namespaces. Tenant-targeted policies match on its presence."
  type        = string
  default     = "platform.refplat.org/tenant"
}

variable "required_workload_labels" {
  description = "Labels every tenant workload must carry (team identity + cost allocation). Keys only; presence is validated."
  type        = list(string)
  default     = ["app.kubernetes.io/name", "team"]
}

# ---------------------------------------------------------------------------
# Engine (Helm)
# ---------------------------------------------------------------------------

variable "helm_chart_version" {
  description = "Version of the Kyverno Helm chart"
  type        = string
  default     = "3.8.1"
}

variable "helm_repository" {
  description = "Repository URL for the Kyverno Helm chart"
  type        = string
  default     = "https://kyverno.github.io/kyverno/"
}

variable "namespace" {
  description = "Dedicated namespace for the Kyverno engine (must not be co-located with other apps)"
  type        = string
  default     = "kyverno"
}

variable "replica_count" {
  description = "Admission controller replica count. Use 3 for HA (platform); 1 is acceptable for cost-sensitive non-prod."
  type        = number
  default     = 3
}

variable "helm_timeout" {
  description = "Timeout for Helm operations in seconds"
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Whether to wait for the Helm releases to become ready"
  type        = bool
  default     = true
}

variable "additional_policies" {
  description = "Raw ClusterPolicy YAML manifests for custom policy injection beyond the built-in set (ADR-014 contract). Keyed by name."
  type        = map(string)
  default     = {}
}

variable "tags" {
  description = "Tags/labels to apply (sanitized to RFC-1123 for K8s labels)"
  type        = map(string)
  default     = {}
}
