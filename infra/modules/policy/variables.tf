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
    "falco",
  ]
}

variable "exclude_principals" {
  description = "Principal (username) wildcards excluded from cluster-scoped policies (RBAC/registry floor) so platform controllers can reconcile addons. Defaults cover the Terraform deployer, ArgoCD, and Kubernetes service controllers."
  type        = list(string)
  default = [
    # PlatformDeployer is the IaC pipeline (Terragrunt/Helm) — it provisions cluster RBAC, so it must
    # not be blocked by the RBAC-hardening policies. EKS presents its username as the assumed-role
    # ARN; the wildcard covers every account + session name. PlatformAdmin is intentionally NOT here
    # (it is read+operate, not author — ADR-040).
    "arn:aws:sts::*:assumed-role/PlatformDeployer/*",
    "system:serviceaccount:argocd:*",
    "system:serviceaccount:kube-system:*",
    "system:nodes:*",
    "system:kube-controller-manager",
    # EKS installs managed add-ons (EBS CSI, etc.) as eks:addon-manager; their upstream RBAC uses
    # wildcards. It is a platform/system installer, not a tenant, so exclude it like kube-system/argocd.
    "eks:addon-manager",
  ]
}

variable "tenant_namespace_label" {
  description = "Namespace label that marks tenant namespaces. Tenant-targeted policies match on its presence."
  type        = string
  default     = "platform.refplat.org/tenant"
}

variable "required_workload_labels" {
  description = "Labels every tenant workload must carry (presence validated). Default is the team cost-allocation label, which the mutate-workload-labels policy auto-injects from the namespace — so apps need no label boilerplate. app.kubernetes.io/name can't be auto-derived under autogen, so it is recommended but not required."
  type        = list(string)
  default     = ["team"]
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

variable "engine_log_verbosity" {
  description = "Kyverno engine log verbosity (--v). 2 is normal; 4-6 surfaces cosign/image-verification detail for debugging. Maps to the chart's features.logging.verbosity."
  type        = number
  default     = 2
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

variable "enable_mutate_defaults" {
  description = "Deploy the mutate policies that auto-inject safe defaults (hardened securityContext, automountServiceAccountToken=false, team/app labels) on tenant workloads. Mutate webhooks fail open. The validate backstops (disallow-privilege-escalation, require-seccomp) deploy regardless."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Image verification (Phase 3 — cosign keyless)
# ---------------------------------------------------------------------------

variable "enable_image_verification" {
  description = "Deploy the per-team verifyImages policies (cosign keyless) and the Kyverno IRSA role granting ECR read (so Kyverno can fetch signatures). Requires app CI to sign images first (#74). Off by default."
  type        = bool
  default     = false
}

variable "verify_failure_action" {
  description = "Audit/Enforce for the verifyImages policies — independent of validation_failure_action so signature verification can roll out Audit-first while the other policies stay Enforce."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Enforce"], var.verify_failure_action)
    error_message = "verify_failure_action must be either \"Audit\" or \"Enforce\"."
  }
}

variable "enable_attestation_verification" {
  description = "Deploy the per-team verify-attestations policies requiring a cosign-signed SBOM (CycloneDX) AND SLSA provenance attestation, in addition to the image signature (#108/108d). Reuses verify_subjects + the Kyverno ECR-read IRSA, so it also requires enable_image_verification = true. Off by default."
  type        = bool
  default     = false
}

variable "attest_failure_action" {
  description = "Audit/Enforce for the verify-attestations policies — separate from verify_failure_action so the SBOM+provenance requirement can roll out Audit-first while signature verification stays Enforce."
  type        = string
  default     = "Audit"

  validation {
    condition     = contains(["Audit", "Enforce"], var.attest_failure_action)
    error_message = "attest_failure_action must be either \"Audit\" or \"Enforce\"."
  }
}

# ---------------------------------------------------------------------------
# Isolated build provenance (SLSA Build L3, #131 P2 — ADR-042)
# ---------------------------------------------------------------------------

variable "trusted_ci_subject_regexp" {
  description = "Anchored regex for the isolated provenance signer's keyless cert subject (the trusted-ci reusable workflow, any pinned ref). Dots escaped; ^...$ anchored so a look-alike repo path can't match."
  type        = string
  default     = "^https://github\\.com/asanexample/trusted-ci/\\.github/workflows/slsa-provenance\\.yml@.+$"
}

variable "attest_caller_repos" {
  description = "Per-team caller repo (org/repo, e.g. asanexample/app-alpha) for the verify-attestations githubWorkflowRepository extension gate. Key = tenant; supplied by the unit ONLY for teams that have adopted the isolated trusted-ci provenance job — for those teams the SLSA provenance attestation must be signed by trusted-ci (gated by this caller repo) instead of the app's own workflow. Teams absent here keep app-signed provenance. Empty = no team uses isolated provenance."
  type        = map(string)
  default     = {}
}

variable "oidc_provider_arn" {
  description = "EKS OIDC provider ARN, for the Kyverno IRSA trust policy. Required when enable_image_verification = true."
  type        = string
  default     = ""
}

variable "oidc_provider_url" {
  description = "EKS OIDC provider URL (no https:// prefix), for the Kyverno IRSA trust policy."
  type        = string
  default     = ""
}

variable "ecr_account_id" {
  description = "AWS account ID hosting the ECR repos Kyverno reads signatures from (the platform account). Cross-account from preprod is permitted by the ECR repo policy."
  type        = string
  default     = ""
}

variable "ecr_region" {
  description = "Region of the ECR repos (for the IRSA policy resource ARN)."
  type        = string
  default     = "us-east-1"
}

variable "verify_subjects" {
  description = "Per-tenant cosign keyless identities (built from teams.hcl at the unit). Key = tenant; value is a LIST of accepted identities (count:1 attestor — any one verifies). A single-element list is the steady state; a 2+ element list supports a zero-downtime signing-identity transition (e.g. a GitHub org migration: accept both old and new org identities until images are re-signed, then drop the old). Per identity: deploy_subject is the exact main-branch workflow identity; preview_subject_regexp matches the PR-preview workflow (its OIDC ref varies per PR)."
  type = map(list(object({
    deploy_subject         = string
    preview_subject_regexp = string
  })))
  default = {}
}

variable "rekor_url" {
  description = "Rekor transparency log URL for keyless verification."
  type        = string
  default     = "https://rekor.sigstore.dev"
}

# ---------------------------------------------------------------------------
# Ingress hostname guard + cleanup (Phase 5)
# ---------------------------------------------------------------------------

variable "enable_httproute_guard" {
  description = "Deploy the per-team Gateway-API route hostname guard (anti-squatting on the shared wildcard listener, ADR-029). Renders only for teams present in tenant_hostname_patterns."
  type        = bool
  default     = true
}

variable "tenant_hostname_patterns" {
  description = "Per-tenant allowed route hostnames/patterns (wildcards ok). Key = tenant; supplied by the unit from teams.hcl. A team's routes may only claim hostnames matching its list. Empty list for a team = no guard rendered for it."
  type        = map(list(string))
  default     = {}
}

variable "enable_cleanup" {
  description = "Deploy the ClusterCleanupPolicy that reaps finished CronJob-spawned Jobs in tenant namespaces."
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
