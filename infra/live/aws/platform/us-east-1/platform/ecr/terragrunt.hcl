include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.ecr
}

inputs = {
  create = true

  # ECR naming convention: team-<team>/<app> (matches teams.hcl app keys).
  # The Team tag scopes per-team access (ABAC, #62) and cost attribution (#61).
  # IMMUTABLE_WITH_EXCLUSION: image tags stay immutable; cosign's sha256-* signature/attestation
  # tags are exempt so an image can carry multiple attestations (SBOM + SLSA provenance) — #114.
  # team-alpha/demo and team-bravo/demo both migrated to Tenant claims (BACK stack P3, #174): the Composition
  # owns the tenant ECR repos now (provider-aws-ecr). This unit retains only non-tenant/platform repos.
  repositories = {
    # The developer portal's own image (Backstage; platform infra, not a tenant app — ADR-051). Built +
    # cosign-signed by the asanexample/backstage repo's CI, pulled by the backstage Deployment on this cluster.
    "platform/backstage" = {
      tag_mutability = "IMMUTABLE_WITH_EXCLUSION" # image tags immutable; cosign sha256-* tags exempt
      tags           = { Service = "backstage" }
    }
    # The self-hosted ARC runner image (platform infra; ADR-065 / #323). Built + cosign-signed by this repo's
    # gha-runner-image.yml from docker/gha-runner/, pulled by the ARC runner scale set on the platform cluster.
    "platform/gha-runner" = {
      tag_mutability = "IMMUTABLE_WITH_EXCLUSION" # image tags immutable; cosign sha256-* tags exempt
      tags           = { Service = "gha-runner" }
    }
    # The triage-copilot agent image (platform infra; ADR-080 — the template platform agent). Built +
    # cosign-signed by the asanexample/triage-copilot repo's CI, pulled by the agent Deployment on this cluster.
    "platform/triage-copilot" = {
      tag_mutability = "IMMUTABLE_WITH_EXCLUSION" # image tags immutable; cosign sha256-* tags exempt
      tags           = { Service = "triage-copilot" }
    }
  }

  # Accounts granted cross-account image pull access
  pull_account_ids = [
    include.base.locals.account_ids["preprod"], # Preprod
    include.base.locals.account_ids["prod"],    # Prod
  ]

  tags = include.base.locals.tags
}
