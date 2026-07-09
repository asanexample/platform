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

locals {
  # ECR pull-through cache credentials. AWS REQUIRES authentication for docker.io / ghcr.io / quay.io — each is
  # gated on its Secrets Manager credential (secret name must start with `ecr-pullthroughcache/`, value
  # {username, accessToken}). Set the ARN to enable that mirror once the secret exists; empty (default) leaves it
  # off. registry.k8s.io is the only credential-free upstream here, so it's always on. ADR-098 D2.
  docker_hub_credential_arn = ""
  ghcr_credential_arn       = ""
  quay_credential_arn       = ""
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
    # The activation operator image (ADR-088): the temporary-power activation controller. Built +
    # cosign-signed + SBOM-attested by this repo's operator-image.yml from operators/activation/, pulled
    # by the activation-operator Terragrunt add-on (digest-pinned) on the platform cluster.
    "platform/activation-operator" = {
      tag_mutability = "IMMUTABLE_WITH_EXCLUSION" # image tags immutable; cosign sha256-* tags exempt
      tags           = { Service = "activation-operator" }
    }
    # The P13 per-team read-isolation proxy image (#590): the fail-closed front door that scopes Grafana
    # datasource queries to the caller's team tenant. Built + cosign-signed + SBOM-attested by this repo's
    # tenant-proxy-image.yml from services/tenant-proxy/, pulled by the tenant-proxy Terragrunt add-on
    # (digest-pinned) on the platform cluster.
    "platform/tenant-proxy" = {
      tag_mutability = "IMMUTABLE_WITH_EXCLUSION" # image tags immutable; cosign sha256-* tags exempt
      tags           = { Service = "tenant-proxy" }
    }
  }

  # Accounts granted cross-account image pull access
  pull_account_ids = [
    include.base.locals.account_ids["preprod"], # Preprod
    include.base.locals.account_ids["prod"],    # Prod
  ]

  # Pull-through cache: mirror public registries into this account on first pull so cluster/CI base-image
  # pulls hit our own ECR (IAM auth, no rate limits) — ADR-098 D2. Only registry.k8s.io supports anonymous
  # pull-through; docker.io / ghcr.io / quay.io REQUIRE a credential (AWS rejects the rule otherwise). Each is
  # gated on its Secrets Manager credential ARN (secret name must start with `ecr-pullthroughcache/`) — set the
  # corresponding local above to enable that mirror once the secret exists; the k8s mirror works standalone.
  pull_through_cache_rules = merge(
    {
      "k8s" = { upstream_registry_url = "registry.k8s.io" }
    },
    local.docker_hub_credential_arn == "" ? {} : {
      "docker-hub" = { upstream_registry_url = "registry-1.docker.io", credential_arn = local.docker_hub_credential_arn }
    },
    local.ghcr_credential_arn == "" ? {} : {
      "ghcr" = { upstream_registry_url = "ghcr.io", credential_arn = local.ghcr_credential_arn }
    },
    local.quay_credential_arn == "" ? {} : {
      "quay" = { upstream_registry_url = "quay.io", credential_arn = local.quay_credential_arn }
    },
  )

  tags = include.base.locals.tags
}
