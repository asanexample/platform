variable "create" {
  description = "Whether to deploy the Actions Runner Controller stack."
  type        = bool
  default     = true
}

variable "cluster_name" {
  description = "EKS cluster the controller + runners run on."
  type        = string
}

variable "region" {
  description = "AWS region (for the ECR registry / future Pod Identity wiring)."
  type        = string
  default     = "us-east-1"
}

# ---------------------------------------------------------------------------
# Namespaces
# ---------------------------------------------------------------------------

variable "controller_namespace" {
  description = "Namespace for the ARC controller (gha-runner-scale-set-controller)."
  type        = string
  default     = "arc-systems"
}

variable "runners_namespace" {
  description = "Namespace for the runner scale set + the runner pods."
  type        = string
  default     = "arc-runners"
}

# ---------------------------------------------------------------------------
# Helm charts (ARC: Autoscaling Runner Scale Sets mode)
# ---------------------------------------------------------------------------

variable "controller_chart_version" {
  description = "gha-runner-scale-set-controller chart version (OCI ghcr.io/actions/actions-runner-controller-charts)."
  type        = string
}

variable "runner_set_chart_version" {
  description = "gha-runner-scale-set chart version (pinned in lockstep with the controller)."
  type        = string
}

variable "helm_timeout" {
  description = "Helm release timeout (seconds)."
  type        = number
  default     = 600
}

variable "helm_wait" {
  description = "Whether Helm waits for the release to become ready."
  type        = bool
  default     = true
}

# ---------------------------------------------------------------------------
# Runner scale set
# ---------------------------------------------------------------------------

variable "github_config_url" {
  description = "GitHub scope the runners register to. Repo-level for the privileged infra-apply pool (ADR-065)."
  type        = string
  default     = "https://github.com/asanexample/platform"
}

variable "runner_scale_set_name" {
  description = "The runner set name — workflows target it via `runs-on: <name>`."
  type        = string
  default     = "platform-infra"
}

variable "runner_image" {
  description = "Full ECR ref (incl. tag) of the custom toolchain runner image (platform/gha-runner). Built by gha-runner-image.yml; bump the tag + re-apply to roll."
  type        = string
}

variable "min_runners" {
  description = "Minimum idle runners (0 = scale to zero)."
  type        = number
  default     = 0
}

variable "max_runners" {
  description = "Maximum concurrent runners."
  type        = number
  default     = 3
}

# ---------------------------------------------------------------------------
# GitHub App credential (via External Secrets → Secrets Manager)
# ---------------------------------------------------------------------------

variable "github_app_secret_name" {
  description = "Secrets Manager key holding the ARC GitHub App creds. JSON properties: appId, installationId, privateKey. Created out-of-band (see the runbook)."
  type        = string
  default     = "platform/gha-runner-controller/github-app"
}

variable "secret_store_name" {
  description = "ClusterSecretStore name the ExternalSecret reads from."
  type        = string
  default     = "aws-secrets-manager"
}

# ---------------------------------------------------------------------------
# Runner AWS identity (Pod Identity → assume PlatformDeployer)
# ---------------------------------------------------------------------------

variable "deployer_role_arn" {
  description = "PlatformDeployer role ARN the runner pods are allowed to assume (to run terragrunt). The runner role exists here, but the actual access is inert until PlatformDeployer's trust admits it (a separate change)."
  type        = string
}

variable "state_role_arn" {
  description = "TerraformStateAccess role ARN (in the management account) the runner assumes for the S3/DynamoDB backend. Terragrunt assumes this SEPARATELY from PlatformDeployer (root.hcl remote_state.role_arn), so a CI apply needs both."
  type        = string
}

variable "runner_service_account" {
  description = "ServiceAccount name for the runner pods (bound to the runner IAM role via Pod Identity)."
  type        = string
  default     = "arc-runner"
}

variable "tags" {
  description = "Tags applied to AWS resources."
  type        = map(string)
  default     = {}
}
