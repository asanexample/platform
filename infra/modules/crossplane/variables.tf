variable "create" {
  description = "Whether to create resources in this module."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Cluster / account context
# ---------------------------------------------------------------------------

variable "cluster_name" {
  description = "EKS cluster name the Crossplane provider runs on (target of the Pod Identity association)."
  type        = string
}

variable "region" {
  description = "AWS region (used to scope the ECR repository ARNs the provisioning role may manage)."
  type        = string
}

variable "account_id" {
  description = "Platform AWS account ID that hosts the tenant ECR repositories the provisioning role manages."
  type        = string
}

# ---------------------------------------------------------------------------
# Crossplane core (Helm)
# ---------------------------------------------------------------------------

variable "namespace" {
  description = "Namespace Crossplane and its providers run in."
  type        = string
  default     = "crossplane-system"
}

variable "helm_chart_version" {
  description = "Crossplane Helm chart version (must be v2.x — this module targets the Crossplane v2 API model)."
  type        = string

  validation {
    condition     = can(regex("^2\\.", var.helm_chart_version))
    error_message = "This module requires Crossplane v2 (chart version must start with '2.')."
  }
}

variable "helm_repository" {
  description = "Crossplane Helm chart repository."
  type        = string
  default     = "https://charts.crossplane.io/stable"
}

variable "helm_wait" {
  description = "Wait for Helm releases to report ready. Keep true so the provider wait-Job gates ProviderConfig."
  type        = bool
  default     = true
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds). Covers provider package download + becoming Healthy."
  type        = number
  default     = 600
}

# ---------------------------------------------------------------------------
# Teardown — robust cluster auth for the destroy-time CR finalizer cleanup.
# Crossplane Provider/XRD/Composition/ProviderConfig CRs carry finalizers the
# package/apiextensions managers drain asynchronously; on teardown that drain
# outlives the helm uninstall timeout (the observed "context deadline exceeded").
# A when=destroy step deletes + force-clears those CRs first (cluster is being
# destroyed, so orphaned packages don't matter) via scripts/k8s-finalizer-clear.sh.
# ---------------------------------------------------------------------------

variable "deployer_role_arn" {
  description = "IAM role ARN to assume for destroy-time CR finalizer cleanup (the PlatformDeployer)"
  type        = string
  default     = ""
}

variable "finalizer_clear_script" {
  description = "Absolute path to scripts/k8s-finalizer-clear.sh (passed from the unit via get_repo_root())"
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# AWS providers (Upbound provider-family-aws)
# ---------------------------------------------------------------------------

variable "provider_registry" {
  description = "OCI registry + org path the provider packages are pulled from."
  type        = string
  default     = "xpkg.upbound.io/upbound"
}

variable "provider_version" {
  description = "Version tag for the AWS provider packages (must be v2.x to run the Crossplane v2 API model and support the PodIdentity credential source)."
  type        = string
  default     = "v2.5.0"
}

variable "provider_services" {
  description = <<-EOT
    AWS provider-family members to install (e.g. "ecr", "iam", "eks"). P1 installs only "ecr" — the
    smallest footprint that proves reconciliation + drift correction. Later phases extend this (and the
    provisioning IAM policy) as the Tenant Composition needs IAM roles / Pod Identity associations.
  EOT
  type        = list(string)
  default     = []
}

# ---------------------------------------------------------------------------
# provider-kubernetes + Composition functions (federated tenant Composition, ADR-048)
# ---------------------------------------------------------------------------

variable "enable_kubernetes_provider" {
  description = "Install provider-kubernetes (in-cluster InjectedIdentity) so a Composition can create the tenant's Kubernetes resources locally. Enabled on workload clusters (preprod/prod), not the platform hub."
  type        = bool
  default     = false
}

variable "kubernetes_provider_package" {
  description = "OCI package ref for provider-kubernetes."
  type        = string
  default     = "xpkg.upbound.io/crossplane-contrib/provider-kubernetes:v1.2.1"
}

variable "kubernetes_provider_hostnetwork" {
  description = "Run provider-kubernetes on hostNetwork (only if its CRDs expose an apiserver-facing webhook unreachable under the overlay). Default false; flip if a conversion/validation webhook is unreachable."
  type        = bool
  default     = false
}

variable "functions" {
  description = "Crossplane Composition Functions to install, as {name, package}. e.g. function-go-templating."
  type = list(object({
    name    = string
    package = string
  }))
  default = []
}

variable "enable_tenant_api" {
  description = "Install the Tenant XRD + Composition (the federated tenant control plane). Workload clusters only."
  type        = bool
  default     = false
}

variable "provider_service_account" {
  description = "ServiceAccount name the provider pods run as (pinned via DeploymentRuntimeConfig so the Pod Identity association can target it). Tenant workloads never use this SA."
  type        = string
  default     = "provider-aws"
}

variable "teams" {
  description = "Canonical Team registry (ADR-049) projected onto the cluster as Team CRs — the envelope subset Kyverno's restrict-tenant-envelope reads. Map of team name -> { ssoGroup, envelope{...}, and canonical-only displayName/developerGroup/costCenter/contacts that are NOT projected }. Empty = no Team CRs. Requires enable_tenant_api (the Team CRD)."
  type        = any
  default     = {}
}

variable "providerconfig_name" {
  description = "Name of the ProviderConfig managed resources reference. 'default' is used when an MR omits providerConfigRef."
  type        = string
  default     = "default"
}

variable "tenant_policy_values" {
  description = "Overrides for the tenant control-plane Kyverno policies chart (restrict-tenant-envelope + restrict-tenant-control-plane), merged over its values.yaml. Keys: validationFailureAction (control-plane, default Enforce), envelopeFailureAction (default Audit — set Enforce at the ADR-049 A6 cutover), failurePolicy, excludePrincipals, commonLabels. Default {} keeps the chart defaults, which reproduce what the policy unit passed pre-move. Only applied when enable_tenant_api."
  type        = any
  default     = {}
}

variable "wait_image" {
  description = "kubectl image for the post-install Job that blocks until providers are Healthy (so the aws.upbound.io ProviderConfig CRD — installed by the provider package, not the core chart — exists before ProviderConfig is applied)."
  type        = string
  default     = "registry.k8s.io/kubectl:v1.35.0"
}

# ---------------------------------------------------------------------------
# Scoped provisioning identity
# ---------------------------------------------------------------------------

variable "tenant_repo_prefix" {
  description = "ECR repository name prefix the provisioning role may manage. Tenant repos are 'team-<team>/<app>', so 'team-' scopes the role to tenant repositories only."
  type        = string
  default     = "team-"
}

# ---------------------------------------------------------------------------
# Tenant provisioning (P2b) — the privileged identity that creates tenant AWS resources
# ---------------------------------------------------------------------------

variable "enable_tenant_provisioning" {
  description = <<-EOT
    Grant the provider's provisioning role the (scoped) permissions to create tenant AWS resources: IAM
    Pod-team roles + EKS Pod Identity associations in this (workload) account, and sts:AssumeRole into the
    platform account for ECR. Also creates the deny-escalation permissions boundary attached to every
    created role. Workload clusters only (preprod/prod), not the platform hub.
  EOT
  type        = bool
  default     = false
}

variable "ecr_provisioner_role_arn" {
  description = "ARN of the platform-account role the provider assumes (assumeRoleChain) to create tenant ECR repositories cross-account. Empty disables the platform-ecr ProviderConfig."
  type        = string
  default     = ""
}

variable "create_developer_cluster_role" {
  description = "Create the shared `tenant-developer` ClusterRole the Composition's per-tenant RoleBindings bind to. False on clusters where the retired v1 `tenant` module owned it (coexistence); true on a fresh v2 build."
  type        = bool
  default     = false
}

variable "ecr_orphan_sweep_role_arn" {
  description = "ARN of a role in the platform/ECR account to assume on teardown to force-delete orphaned tenant ECR repos (team-*) the Composition created — typically the platform PlatformDeployer (assumable by the teardown's profile). Empty disables the sweep."
  type        = string
  default     = ""
}

variable "tenant_role_name_prefix" {
  description = "Name prefix for the IAM roles the provisioning role may create/manage (the tenant workload roles). Scopes iam:* on the provisioning role."
  type        = string
  default     = "Pod-team-"
}

variable "developer_role_name_prefix" {
  description = "Name prefix for the per-team developer-access IAM roles the Composition provisions (P2c). Also scoped by the provisioning role's iam:* statements alongside tenant_role_name_prefix."
  type        = string
  default     = "DeveloperAccess-"
}

variable "management_account_id" {
  description = "Management (org) AWS account ID. Used by the Composition's DeveloperAccess role trust policy to allow the per-team SSO permission set (Dev-<team>) in both the management and workload accounts to assume the role. Empty disables the SSO trust condition."
  type        = string
  default     = ""
}

# ---------------------------------------------------------------------------
# Tenant API environment (P2b) — cluster constants injected into the Composition via EnvironmentConfig
# ---------------------------------------------------------------------------

variable "ecr_registry" {
  description = "Platform-account ECR registry host (<platform-acct>.dkr.ecr.<region>.amazonaws.com). Used by the Composition for per-team image registry policies + ECR repo creation."
  type        = string
  default     = ""
}

variable "base_domain" {
  description = "Per-cluster ingress domain for tenant app hostnames (e.g. preprod.aws.refplat.org). The Composition derives each app's allowed route hostnames from it as <app>-<team>.<base_domain> + the <app>-<team>-pr-* preview wildcard (ADR-060). Empty = derive nothing (only explicit spec.hostnames are allowed)."
  type        = string
  default     = ""
}

variable "tenant_pull_account_ids" {
  description = "AWS account IDs granted cross-account image pull on tenant ECR repos (the workload accounts). Mirrors the ecr unit's pull_account_ids."
  type        = list(string)
  default     = []
}

variable "tags" {
  description = "Tags applied to AWS resources created by this module."
  type        = map(string)
  default     = {}
}
