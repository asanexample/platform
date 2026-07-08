variable "create" {
  description = "Whether to create ECR repositories"
  type        = bool
  default     = true
}

variable "repositories" {
  description = "Map of repository names to configuration. Keys are repo names (e.g. 'team-alpha/app'). Set tag_mutability = IMMUTABLE_WITH_EXCLUSION to keep image tags immutable while exempting cosign's sha256-* tags (see tag_mutability_exclusion_filters)."
  type = map(object({
    tag_mutability = optional(string, "IMMUTABLE")
    tags           = optional(map(string), {}) # merged onto var.tags (e.g. { Team = "alpha" })
  }))
  default = {}

  validation {
    condition     = alltrue([for r in values(var.repositories) : contains(["MUTABLE", "IMMUTABLE", "IMMUTABLE_WITH_EXCLUSION", "MUTABLE_WITH_EXCLUSION"], r.tag_mutability)])
    error_message = "tag_mutability must be one of: MUTABLE, IMMUTABLE, IMMUTABLE_WITH_EXCLUSION, MUTABLE_WITH_EXCLUSION."
  }
}

variable "tag_mutability_exclusion_filters" {
  description = "WILDCARD tag patterns exempted from immutability for repos using tag_mutability = IMMUTABLE_WITH_EXCLUSION. Default exempts cosign's `sha256-*` signature/attestation tags so they can be updated (needed to hold multiple attestations — SBOM + provenance) while image tags stay immutable."
  type        = list(string)
  default     = ["sha256-*"]

  validation {
    condition     = length(var.tag_mutability_exclusion_filters) <= 5
    error_message = "ECR allows at most 5 tag-mutability exclusion filters."
  }
}

variable "pull_account_ids" {
  description = "AWS account IDs allowed to pull images cross-account"
  type        = list(string)
  default     = []
}

variable "max_image_count" {
  description = "Maximum number of tagged images to retain per repository"
  type        = number
  default     = 50
}

variable "pull_through_cache_rules" {
  description = "ECR pull-through cache rules that lazily mirror public registries into this account. Keys are the local repository prefix (e.g. 'docker-hub'); a first pull of `<acct>.dkr.ecr.<region>.amazonaws.com/<prefix>/<image>` caches the upstream image. credential_arn (optional) is a Secrets Manager secret ARN — its name MUST start with `ecr-pullthroughcache/` — required for authenticated upstreams like Docker Hub; anonymous upstreams (ghcr.io, quay.io, registry.k8s.io) omit it."
  type = map(object({
    upstream_registry_url = string
    credential_arn        = optional(string)
  }))
  default = {}
}

variable "force_delete" {
  description = "Whether to allow deletion of non-empty repositories"
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags to apply to all resources"
  type        = map(string)
  default     = {}
}
