# TechDocs storage (#938, ADR-097). A private, versioned, SSE-S3 bucket that holds the pre-built
# learning-portal TechDocs site. CI (.github/workflows/techdocs.yml) generates the site with mkdocs +
# the techdocs-cli and publishes it here (builder: external); Backstage serves it read-only.
#
# Access is same-account (platform), so it is granted by IDENTITY policies, not a bucket policy:
#   - write: the `github-actions-techdocs-publish` OIDC role (see the github-oidc unit).
#   - read:  the Backstage Pod-Identity reader role (see the backstage module — Phase 4).
# Both roles live in the platform account, so reader_role_arns/writer_role_arns are left empty (the
# aws/s3 module only attaches a bucket policy for cross-account grants).
include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.s3
}

inputs = {
  create = true
  buckets = {
    "refplat-platform-techdocs" = {
      # Same-account read/write is granted on the roles' own identity policies (no bucket policy needed).
      reader_role_arns = []
      writer_role_arns = []
      tags = {
        Component = "techdocs"
        Purpose   = "learning-portal-techdocs-site"
      }
    }
  }
}
