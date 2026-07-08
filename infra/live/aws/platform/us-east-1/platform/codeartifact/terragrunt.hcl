include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.codeartifact
}

locals {
  # ---------------------------------------------------------------------------
  # One consumer repository per PRODUCT, derived from the Product registry
  # (gitops/products/<team>/<product>.yaml) — same fileset+yamldecode derivation as `github-oidc`/`policy`
  # (ADR-069). Each Product repo holds that Product's private packages and pulls public deps through the
  # shared store repos (below) as upstreams. CodeArtifact is the language-package sibling to ECR (ADR-098/028).
  # ---------------------------------------------------------------------------
  products_dir = "${get_repo_root()}/gitops/products"
  products = {
    for f in fileset(local.products_dir, "**/*.yaml") :
    yamldecode(file("${local.products_dir}/${f}")).metadata.name => {
      team    = yamldecode(file("${local.products_dir}/${f}")).spec.team
      product = trimsuffix(basename(f), ".yaml") # short name (the filename) = the gitops/.../<product>.yaml stem
    }
  }

  # The store repos every Product consumes public dependencies through.
  store_upstreams = ["npm-store", "pypi-store", "maven-store", "nuget-store"]

  product_repositories = { for key, p in local.products :
    key => {
      description = "Packages for Product ${key} (team ${p.team})"
      upstreams   = local.store_upstreams
      tags        = { Team = p.team, Product = p.product }
    }
  }
}

inputs = {
  create = true

  # Domain = the dedupe + KMS-encryption boundary for all repositories (one CMK, one asset store).
  domain_name = "refplat"

  # Store repos: one external connection each (an AWS limit), proxying + caching a public source. Consumer
  # repos reference these as upstreams, so a public package is fetched once and served from the domain after.
  store_repositories = {
    "npm-store"   = { external_connection = "public:npmjs", description = "Proxy + cache of npmjs.org" }
    "pypi-store"  = { external_connection = "public:pypi", description = "Proxy + cache of PyPI" }
    "maven-store" = { external_connection = "public:maven-central", description = "Proxy + cache of Maven Central" }
    "nuget-store" = { external_connection = "public:nuget-org", description = "Proxy + cache of NuGet Gallery" }
  }

  # Per-Product consumer repos (local.product_repositories, ADR-069) — derived from the Product registry,
  # not hand-listed. Note: Go is not a CodeArtifact format (ADR-098 D5) — handled out of band.
  repositories = local.product_repositories

  # Accounts granted cross-account read (pull): preprod + prod, mirroring ECR's pull_account_ids.
  read_account_ids = [
    include.base.locals.account_ids["preprod"], # Preprod
    include.base.locals.account_ids["prod"],    # Prod
  ]

  tags = include.base.locals.tags
}
