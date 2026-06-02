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

variable "providerconfig_name" {
  description = "Name of the ProviderConfig managed resources reference. 'default' is used when an MR omits providerConfigRef."
  type        = string
  default     = "default"
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

variable "tenant_role_name_prefix" {
  description = "Name prefix for the IAM roles the provisioning role may create/manage (the tenant workload roles). Scopes iam:* on the provisioning role."
  type        = string
  default     = "Pod-team-"
}

# ---------------------------------------------------------------------------
# Tenant API environment (P2b) — cluster constants injected into the Composition via EnvironmentConfig
# ---------------------------------------------------------------------------

variable "ecr_registry" {
  description = "Platform-account ECR registry host (<platform-acct>.dkr.ecr.<region>.amazonaws.com). Used by the Composition for per-team image registry policies + ECR repo creation."
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
