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
  # team-alpha/demo migrated to the Tenant claim (BACK stack P3, #174): the Composition now owns alpha's ECR
  # repo (provider-aws-ecr), so it's removed here to avoid two owners. bravo stays until it migrates too.
  repositories = {
    "team-bravo/demo" = { tag_mutability = "IMMUTABLE_WITH_EXCLUSION", tags = { Team = "bravo" } }
  }

  # Accounts granted cross-account image pull access
  pull_account_ids = [
    include.base.locals.account_ids["preprod"], # Preprod
    include.base.locals.account_ids["prod"],    # Prod
  ]

  tags = include.base.locals.tags
}
