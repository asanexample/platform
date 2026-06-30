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
  description = "Container image registry prefixes admitted cluster-wide (e.g. the platform ECR host). The cluster-wide floor; per-environment scoping is layered on top via tenant_registry_map."
  type        = list(string)
  default     = []
}

variable "exclude_namespaces" {
  description = "Infrastructure namespaces excluded from environment-targeted and cluster-scoped policies so Kyverno never gates platform/system workloads."
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
    "observability",
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
    # ArgoCD delivers environment claims via GitOps (BACK stack Phase 1). When it reconciles a managed (preprod)
    # cluster it assumes the ArgoCD IAM role, so EKS presents it as the assumed-role ARN — NOT the argocd pod
    # SA below (which only covers ArgoCD running *in-cluster*). Without this, restrict-environment-control-plane
    # would deny ArgoCD-applied XTenants. ArgoCD already holds cluster-admin on the managed cluster, so this
    # grants no new privilege; the trust boundary is git review + ArgoCD RBAC.
    "arn:aws:sts::*:assumed-role/ArgoCD/*",
    "system:serviceaccount:argocd:*",
    "system:serviceaccount:kube-system:*",
    "system:nodes:*",
    "system:kube-controller-manager",
    # EKS installs managed add-ons (EBS CSI, etc.) as eks:addon-manager; their upstream RBAC uses
    # wildcards. It is a platform/system installer, not an environment, so exclude it like kube-system/argocd.
    "eks:addon-manager",
  ]
}

variable "extra_exclude_namespaces" {
  description = "Additional infrastructure namespaces to exclude, appended to exclude_namespaces. Use this to add per-environment platform add-ons (e.g. crossplane-system) without restating the full default list."
  type        = list(string)
  default     = []
}

variable "extra_exclude_principals" {
  description = "Additional principal (username) wildcards to exclude, appended to exclude_principals. Use this for per-environment platform controllers that author wildcard RBAC (e.g. Crossplane's rbac-manager) without restating the full default list."
  type        = list(string)
  default     = []
}

variable "environment_namespace_label" {
  description = "Namespace label that marks environment namespaces. Environment-targeted policies match on its presence."
  type        = string
  default     = "platform.refplat.org/team"
}

variable "required_workload_labels" {
  description = "Labels every environment workload must carry (presence validated). Default is the team cost-allocation label, which the mutate-workload-labels policy auto-injects from the namespace — so apps need no label boilerplate. app.kubernetes.io/name can't be auto-derived under autogen, so it is recommended but not required."
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

variable "cluster_name" {
  description = "EKS cluster name (for the Kyverno ECR-read Pod Identity association)."
  type        = string
  default     = ""
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
  description = "Deploy the mutate policies that auto-inject safe defaults (hardened securityContext, automountServiceAccountToken=false, team/app labels, graceful-drain preStop + terminationGracePeriodSeconds) on environment workloads. Mutate webhooks fail open. The validate backstops (disallow-privilege-escalation, require-seccomp) deploy regardless."
  type        = bool
  default     = true
}

variable "enable_pdb_generate" {
  description = "Generate a default maxUnavailable=1 PodDisruptionBudget per environment Deployment/StatefulSet, with a selector copied from the workload's own matchLabels (ADR-085). Also installs the ClusterRole that lets Kyverno's background controller create the PDBs. Drain-safe by construction (never blocks a node drain)."
  type        = bool
  default     = true
}

variable "enable_topology_spread" {
  description = "Inject topologySpreadConstraints (zone + node, soft/ScheduleAnyway) on environment Deployments/StatefulSets when absent, with a labelSelector derived from the workload's own selector (ADR-085) — so replicas don't all land on one node/AZ. add-if-absent; applies on admission (existing workloads pick it up on next deploy)."
  type        = bool
  default     = true
}

variable "enable_replica_floor" {
  description = "Deploy the require-prod-replica-floor validate policy: prod-stage environment workloads (<team>-<product>-prod) must run spec.replicas >= 2 (ADR-085). Lower stages are unaffected (cost)."
  type        = bool
  default     = true
}

variable "enable_rollout_kind" {
  description = "Also match the Argo Rollouts `Rollout` kind in the availability policies (PDB-generate, topology-spread, replica-floor, default-namespace) for ADR-056. Default false: a Kyverno rule naming a kind whose CRD is absent fails to create (#7839), so enable per cluster ONLY after the argo-rollouts unit (CRDs) is applied there."
  type        = bool
  default     = false
}

variable "replica_floor_failure_action" {
  description = "failureAction for require-prod-replica-floor — its own knob so it rolls Audit-first even where the cluster-wide validationFailureAction is Enforce. Flip to Enforce after reviewing the Audit PolicyReports."
  type        = string
  default     = "Audit"
  validation {
    condition     = contains(["Audit", "Enforce"], var.replica_floor_failure_action)
    error_message = "replica_floor_failure_action must be Audit or Enforce."
  }
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

variable "trusted_ci_build_subject_regexp" {
  description = "Anchored regex for the shared build-sign reusable workflow's keyless cert subject (asanexample/trusted-ci/build-sign.yml, any pinned ref). Dots escaped; ^...$ anchored. The image signature + SBOM for shared-signer teams (see shared_signer_caller_repos) are signed by this identity."
  type        = string
  default     = "^https://github\\.com/asanexample/trusted-ci/\\.github/workflows/build-sign\\.yml@.+$"
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

variable "verify_subjects_product" {
  description = "v3 (ADR-067/069 §6): per-PRODUCT cosign keyless verification, derived from gitops/products at the unit (the per-team verify_subjects analog). Key = <team>-<product>. team/product select the product's environment namespaces by label (set by the Composition); repo is the githubWorkflowRepository gate for the shared trusted-ci build-sign signer; registryPrefix is team-<team>/<product> (the policy appends -*). appSubjects: optional per-product app-signed identities for bespoke-build products."
  type = map(object({
    team           = string
    product        = string
    repo           = string
    registryPrefix = string
    appSubjects = optional(list(object({
      deploy_subject         = string
      preview_subject_regexp = string
    })), [])
  }))
  default = {}
}

variable "rekor_url" {
  description = "Rekor transparency log URL for keyless verification."
  type        = string
  default     = "https://rekor.sigstore.dev"
}

# ---------------------------------------------------------------------------
# Cleanup (Phase 5). The per-team route hostname guard (enable_httproute_guard / tenant_hostname_patterns) was
# removed at the v3 cutover — restrict-route-hostnames is Composition-owned per-Environment (ADR-067/069 §2).
# ---------------------------------------------------------------------------

variable "enable_cleanup" {
  description = "Deploy the ClusterCleanupPolicy that reaps finished CronJob-spawned Jobs in environment namespaces."
  type        = bool
  default     = true
}

variable "additional_policies" {
  description = "Raw ClusterPolicy YAML manifests for custom policy injection beyond the built-in set (ADR-014 contract). Keyed by name."
  type        = map(string)
  default     = {}
}

variable "webhook_host_network" {
  description = "Run the admission/cleanup webhook servers on hostNetwork (node VPC IP). Required on EKS with an overlay CNI (Cilium cluster-pool), where the managed control plane cannot route to overlay pod IPs. Leave false for VPC-routable (ENI) datapaths."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags/labels to apply (sanitized to RFC-1123 for K8s labels)"
  type        = map(string)
  default     = {}
}

variable "enable_cost_budget_enforcement" {
  description = "Enable the Kyverno policy that blocks new XEnvironment provisioning for over-budget teams (ADR-091 Phase C). Reads the cost-budget-status ConfigMap maintained by the budget-enforcement annotator."
  type        = bool
  default     = false
}

variable "cost_budget_status_namespace" {
  description = "Namespace holding the cost-budget-status ConfigMap the over-budget policy reads (ADR-091 Phase C)."
  type        = string
  default     = "observability"
}

variable "cost_budget_failure_action" {
  description = "Audit or Enforce for the over-budget provisioning policy (ADR-091 Phase C). Audit-first, like every other policy."
  type        = string
  default     = "Audit"
}

variable "cost_budget_failure_policy" {
  description = "Kyverno failurePolicy for the over-budget policy (ADR-091 Phase C). Ignore = fail-open (an observability outage never blocks provisioning) — recommended."
  type        = string
  default     = "Ignore"
}
