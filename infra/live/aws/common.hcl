# Common variables shared across all regions and environments
# This file contains global configuration for the AWS platform

locals {
  # Load secrets (account IDs, emails, SSO config)
  _secrets = read_terragrunt_config("${get_repo_root()}/infra/live/aws/secrets.hcl")

  # Account IDs and emails (flattened from secrets)
  account_ids    = local._secrets.locals.account_ids
  admin_email    = local._secrets.locals.admin_email
  account_emails = local._secrets.locals.account_emails

  # External service IDs
  cloudflare_zone_id = local._secrets.locals.cloudflare_zone_id

  # ArgoCD SSO (Identity Center SAML)
  argocd_sso_url     = local._secrets.locals.argocd_sso_url
  argocd_sso_ca_data = local._secrets.locals.argocd_sso_ca_data

  # Dex SSO broker (Identity Center SAML). try()-guarded so existing units don't break before the
  # manual Dex SAML app is set up and these keys are added to secrets.hcl (see docs/runbooks/dex-sso.md).
  dex_sso_url     = try(local._secrets.locals.dex_sso_url, "")
  dex_sso_ca_data = try(local._secrets.locals.dex_sso_ca_data, "")

  # Environment -> AWS account ID mapping (safety validation)
  # Used by _base.hcl to verify env.hcl account_id matches the expected value.
  environment_account_map = local._secrets.locals.account_ids

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
}
