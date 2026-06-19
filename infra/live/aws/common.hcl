# Common variables shared across all regions and environments
# This file contains global configuration for the AWS platform

locals {
  # Load config secrets (account IDs, emails, SSO config), ADR-066. Normally decrypted inline from the committed
  # SOPS secrets.enc.yaml via the management platform-sops KMS key. TG_SOPS_BOOTSTRAP=1 is the greenfield escape:
  # it falls back to the local plaintext secrets.hcl, needed ONLY on a true from-zero bootstrap before that key
  # exists (its own unit + state-bootstrap include root.hcl, so they can't decrypt what isn't created yet). Both
  # branches yield the same FLAT map, so local._secrets.X accessors are identical. Terragrunt short-circuits the
  # conditional, so the un-taken branch's file is never read (mirrors root.hcl's TG_FORCE_DEPLOYER escape).
  _secrets = get_env("TG_SOPS_BOOTSTRAP", "") == "1" ? read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl").locals : yamldecode(sops_decrypt_file("${get_repo_root()}/infra/live/aws/secrets.enc.yaml"))

  # Account IDs and emails (flattened from secrets)
  account_ids    = local._secrets.account_ids
  admin_email    = local._secrets.admin_email
  account_emails = local._secrets.account_emails

  # External service IDs
  cloudflare_zone_id = local._secrets.cloudflare_zone_id

  # ArgoCD SSO (Identity Center SAML)
  argocd_sso_url     = local._secrets.argocd_sso_url
  argocd_sso_ca_data = local._secrets.argocd_sso_ca_data

  # Keycloak app-IdP broker (Identity Center SAML, ADR-053). try()-guarded like Dex's — set after the manual
  # Keycloak SAML app exists (docs/runbooks/keycloak-sso.md). ca_data is the bare base64 cert body.
  keycloak_sso_url     = try(local._secrets.keycloak_sso_url, "")
  keycloak_sso_ca_data = try(local._secrets.keycloak_sso_ca_data, "")

  # Environment -> AWS account ID mapping (safety validation)
  # Used by _base.hcl to verify env.hcl account_id matches the expected value.
  environment_account_map = local._secrets.account_ids

  # Project variables
  workload = "platform"

  # Org/resource name prefix for globally- or account-unique resource names (e.g. tenant S3 buckets
  # `${org_name}-team-<team>-<suffix>`). Matches the GitHub org. Change here to rebrand the platform.
  org_name = "asanexample"

  # Common tags
  tags = {
    ManagedBy          = "Terragrunt"
    Project            = "Multi-Cloud Platform"
    DataClassification = "Internal"
    CostCenter         = "Engineering"
    Owner              = "Platform Team"
    # Default owner for cross-cutting/platform resources; team-owned resources
    # (ECR repos, per-team IAM roles) override this with their team (#61).
    Team = "platform"
  }

  # ---------------------------------------------------------------------------
  # Cost / environment profile (dev = cost-optimized). Flip these to go prod-grade.
  # Overridable per-env in env.hcl (the env layer wins in _base.hcl's all_vars merge).
  # See docs/plans/cost-optimized-dev-rebuild.md.
  # ---------------------------------------------------------------------------
  cost_profile = "dev"   # ONE SWITCH. "dev" = cost-optimized (single-AZ, single-replica, durable stores off); "prod" = HA (RF3, multi-AZ, stores on). Per-knob overrides (high_availability / single_az_nodes / enable_mimir / enable_loki) win over the preset — set them here or in env.hcl.
  node_arch    = "arm64" # Graviton (cheaper, prod-grade); independent of cost_profile. "amd64" = t3 / x86.
}
