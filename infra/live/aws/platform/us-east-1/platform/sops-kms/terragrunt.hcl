include "base" {
  path   = find_in_parent_folders("aws/_base.hcl")
  expose = true
}

include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = include.base.locals.module_source.sops_kms
}

# SOPS config-encryption key (ADR-066). Encrypts infra/live/aws/secrets.enc.yaml; root.hcl + common.hcl decrypt
# it inline. It's bootstrap-tier — every other unit's config load depends on this key existing.
#
# NOTE (#305 / ADR-066): this unit is created here while the config is still plaintext (secrets.hcl). Once the
# config flips to SOPS (root.hcl/common.hcl -> sops_decrypt_file), re-applying this unit decrypts secrets.enc.yaml
# with the key it already owns — fine on day 2. Making it from-scratch-bootstrap-safe (no secrets chain) is a
# documented follow-up; the platform is not being rebuilt now.
inputs = {
  create     = true
  alias_name = "platform-sops"

  # Operators authenticate from management or platform (SSO AdministratorAccess) — encrypt + decrypt.
  operator_account_roots = [
    "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:root",
    "arn:aws:iam::${include.base.locals.account_ids["platform"]}:root",
  ]
  operator_principal_patterns = [
    "arn:aws:iam::${include.base.locals.account_ids["mgmt"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
    "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/aws-reserved/sso.amazonaws.com/AWSReservedSSO_AdministratorAccess_*",
  ]

  # The ARC runner reads config in CI (decrypt only); same account as the key, granted by the key policy.
  decrypt_principal_arns = [
    "arn:aws:iam::${include.base.locals.account_ids["platform"]}:role/platform-use1-eks-arc-runner",
  ]

  tags = include.base.locals.tags
}
